import 'dart:convert';

import '../../../core/storage/app_database.dart';
import '../domain/transfer_history_record.dart';

class TransferHistoryRepository {
  TransferHistoryRepository({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  Future<void> addRecord({
    required String id,
    String? requestId,
    required TransferHistoryDirection direction,
    required String peerName,
    String? peerIp,
    required String rootPath,
    required List<String> savedPaths,
    required int fileCount,
    required int totalBytes,
    required TransferHistoryStatus status,
    required int createdAtMs,
  }) async {
    final db = await _database.database;
    await db.insert(AppDatabase.transferHistoryTable, <String, Object?>{
      'id': id,
      'request_id': requestId,
      'direction': direction.name,
      'peer_name': peerName.trim().isEmpty ? 'Unknown peer' : peerName.trim(),
      'peer_ip': peerIp?.trim(),
      'root_path': rootPath,
      'saved_paths_json': jsonEncode(savedPaths),
      'file_count': fileCount,
      'total_bytes': totalBytes,
      'status': status.name,
      'created_at': createdAtMs,
    });
  }

  Future<List<TransferHistoryRecord>> listRecords({
    TransferHistoryDirection? direction,
    int limit = 100,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.transferHistoryTable,
      where: direction == null ? null : 'direction = ?',
      whereArgs: direction == null ? null : <Object?>[direction.name],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return rows.map(_mapRow).toList(growable: false);
  }

  TransferHistoryRecord _mapRow(Map<String, Object?> row) {
    final savedPathsRaw = row['saved_paths_json'] as String? ?? '[]';
    final decoded = jsonDecode(savedPathsRaw);
    final savedPaths = decoded is List<dynamic>
        ? decoded.whereType<String>().toList(growable: false)
        : <String>[];

    return TransferHistoryRecord(
      id: row['id'] as String,
      requestId: row['request_id'] as String?,
      direction: TransferHistoryDirection.values.byName(
        row['direction'] as String,
      ),
      peerName: row['peer_name'] as String,
      peerIp: row['peer_ip'] as String?,
      rootPath: row['root_path'] as String,
      savedPaths: savedPaths,
      fileCount: (row['file_count'] as num).toInt(),
      totalBytes: (row['total_bytes'] as num).toInt(),
      status: TransferHistoryStatus.values.byName(row['status'] as String),
      createdAtMs: (row['created_at'] as num).toInt(),
    );
  }
}
