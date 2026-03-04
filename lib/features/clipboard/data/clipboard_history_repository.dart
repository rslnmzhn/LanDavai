import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../domain/clipboard_entry.dart';

class ClipboardHistoryRepository {
  ClipboardHistoryRepository({required AppDatabase database})
    : _databaseProvider = (() async => database.database);

  ClipboardHistoryRepository.withDatabaseProvider({
    required Future<Database> Function() databaseProvider,
  }) : _databaseProvider = databaseProvider;

  final Future<Database> Function() _databaseProvider;

  Future<List<ClipboardHistoryEntry>> listRecent({int? limit}) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      AppDatabase.clipboardHistoryTable,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_mapRow).toList(growable: false);
  }

  Future<ClipboardHistoryEntry?> findLatest() async {
    final rows = await listRecent(limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<bool> hasHash(String contentHash) async {
    final normalized = contentHash.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final db = await _databaseProvider();
    final rows = await db.query(
      AppDatabase.clipboardHistoryTable,
      columns: <String>['id'],
      where: 'content_hash = ?',
      whereArgs: <Object>[normalized],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> insert(ClipboardHistoryEntry entry) async {
    final db = await _databaseProvider();
    await db.insert(
      AppDatabase.clipboardHistoryTable,
      <String, Object?>{
        'id': entry.id,
        'entry_type': entry.type.value,
        'content_hash': entry.contentHash,
        'text_value': entry.textValue,
        'image_path': entry.imagePath,
        'created_at': entry.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ClipboardHistoryEntry>> trimToMaxEntries(int maxEntries) async {
    if (maxEntries <= 0) {
      return const <ClipboardHistoryEntry>[];
    }
    final db = await _databaseProvider();
    final overLimitRows = await db.query(
      AppDatabase.clipboardHistoryTable,
      orderBy: 'created_at DESC',
      offset: maxEntries,
    );
    if (overLimitRows.isEmpty) {
      return const <ClipboardHistoryEntry>[];
    }

    final toDelete = overLimitRows.map(_mapRow).toList(growable: false);
    final ids = toDelete.map((entry) => entry.id).toList(growable: false);
    final placeholders = List<String>.filled(ids.length, '?').join(', ');

    await db.delete(
      AppDatabase.clipboardHistoryTable,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return toDelete;
  }

  Future<ClipboardHistoryEntry?> findById(String id) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      AppDatabase.clipboardHistoryTable,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapRow(rows.first);
  }

  Future<ClipboardHistoryEntry?> deleteById(String id) async {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final db = await _databaseProvider();
    return db.transaction((txn) async {
      final rows = await txn.query(
        AppDatabase.clipboardHistoryTable,
        where: 'id = ?',
        whereArgs: <Object>[normalized],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }

      final mapped = _mapRow(rows.first);
      await txn.delete(
        AppDatabase.clipboardHistoryTable,
        where: 'id = ?',
        whereArgs: <Object>[normalized],
      );
      return mapped;
    });
  }

  ClipboardHistoryEntry _mapRow(Map<String, Object?> row) {
    return ClipboardHistoryEntry(
      id: row['id']! as String,
      type: ClipboardEntryTypeX.fromValue(row['entry_type']! as String),
      contentHash: row['content_hash']! as String,
      textValue: row['text_value'] as String?,
      imagePath: row['image_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }
}
