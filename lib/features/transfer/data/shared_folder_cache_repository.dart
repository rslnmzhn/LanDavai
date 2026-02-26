import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../../core/storage/app_database.dart';
import '../../discovery/data/device_alias_repository.dart';
import '../domain/shared_folder_cache.dart';
import 'thumbnail_cache_service.dart';

class SharedFolderCacheRepository {
  SharedFolderCacheRepository({
    required AppDatabase database,
    ThumbnailCacheService? thumbnailCacheService,
  }) : _database = database,
       _thumbnailCacheService =
           thumbnailCacheService ?? ThumbnailCacheService(database: database);

  final AppDatabase _database;
  final ThumbnailCacheService _thumbnailCacheService;
  static const int _schemaVersion = 1;

  bool supportsPreviewForPath(String relativePath) {
    return _thumbnailCacheService.supportsThumbnailForPath(relativePath);
  }

  bool isVideoPath(String relativePath) {
    return _thumbnailCacheService.isVideoPath(relativePath);
  }

  Future<SharedFolderCacheRecord> buildOwnerCache({
    required String ownerMacAddress,
    required String folderPath,
    String? displayName,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final rootDirectory = Directory(folderPath);
    if (!await rootDirectory.exists()) {
      throw ArgumentError('Directory does not exist: $folderPath');
    }

    final normalizedRoot = p.normalize(rootDirectory.absolute.path);
    final resolvedDisplayName = _resolveDisplayName(
      providedName: displayName,
      fallbackPath: normalizedRoot,
    );
    final cacheId = _createCacheId(
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootIdentity: normalizedRoot,
    );

    final entries = await _indexFolder(normalizedRoot, cacheId: cacheId);
    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    final cacheDir = await _database.resolveSharedCacheDirectory();
    final fileName = _createCacheFileName(
      role: SharedFolderCacheRole.owner,
      displayName: resolvedDisplayName,
      cacheId: cacheId,
    );
    final indexPath = p.join(cacheDir.path, fileName);

    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: normalizedRoot,
      displayName: resolvedDisplayName,
      indexFilePath: indexPath,
      itemCount: entries.length,
      totalBytes: totalBytes,
      updatedAtMs: now,
    );

    await _writeIndexFile(record, entries);
    await _upsertRecord(record);
    return record;
  }

  Future<SharedFolderCacheRecord> buildOwnerSelectionCache({
    required String ownerMacAddress,
    required List<String> filePaths,
    String? displayName,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final normalizedPaths =
        filePaths
            .map((path) => p.normalize(File(path).absolute.path))
            .toSet()
            .toList(growable: false)
          ..sort();

    if (normalizedPaths.isEmpty) {
      throw ArgumentError('filePaths must not be empty.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final rootIdentity = normalizedPaths.join('|');
    final cacheId = _createCacheId(
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootIdentity: rootIdentity,
    );

    final entries = <SharedFolderIndexEntry>[];
    for (final absolutePath in normalizedPaths) {
      final file = File(absolutePath);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }

      final relativePath = p.basename(absolutePath);
      final thumbnail = await _thumbnailCacheService.ensureOwnerThumbnail(
        cacheId: cacheId,
        relativePath: relativePath,
        sourcePath: absolutePath,
        sizeBytes: stat.size,
        modifiedAtMs: stat.modified.millisecondsSinceEpoch,
      );
      entries.add(
        SharedFolderIndexEntry(
          relativePath: relativePath,
          sizeBytes: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
          absolutePath: absolutePath,
          thumbnailId: thumbnail?.thumbnailId,
        ),
      );
    }

    if (entries.isEmpty) {
      throw ArgumentError('None of the selected files are accessible.');
    }

    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );

    final resolvedDisplayName = _resolveDisplayName(
      providedName: displayName,
      fallbackPath: 'Selected files',
    );
    final cacheDir = await _database.resolveSharedCacheDirectory();
    final fileName = _createCacheFileName(
      role: SharedFolderCacheRole.owner,
      displayName: resolvedDisplayName,
      cacheId: cacheId,
    );
    final indexPath = p.join(cacheDir.path, fileName);

    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: 'selection://$cacheId',
      displayName: resolvedDisplayName,
      indexFilePath: indexPath,
      itemCount: entries.length,
      totalBytes: totalBytes,
      updatedAtMs: now,
    );

    await _writeIndexFile(record, entries);
    await _upsertRecord(record);
    return record;
  }

  Future<SharedFolderCacheRecord> saveReceiverCache({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required String remoteFolderIdentity,
    required String remoteDisplayName,
    required List<SharedFolderIndexEntry> entries,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final receiverMac = _normalizeOrThrow(
      receiverMacAddress,
      field: 'receiverMacAddress',
    );
    final rootIdentity = remoteFolderIdentity.trim();
    if (rootIdentity.isEmpty) {
      throw ArgumentError('remoteFolderIdentity must not be empty.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );
    final displayName = remoteDisplayName.trim().isEmpty
        ? 'Shared folder'
        : remoteDisplayName.trim();
    final cacheId = _createCacheId(
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
      rootIdentity: rootIdentity,
    );

    final cacheDir = await _database.resolveSharedCacheDirectory();
    final fileName = _createCacheFileName(
      role: SharedFolderCacheRole.receiver,
      displayName: displayName,
      cacheId: cacheId,
    );
    final indexPath = p.join(cacheDir.path, fileName);

    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
      rootPath: rootIdentity,
      displayName: displayName,
      indexFilePath: indexPath,
      itemCount: entries.length,
      totalBytes: totalBytes,
      updatedAtMs: now,
    );

    await _writeIndexFile(record, entries);
    await _upsertRecord(record);
    return record;
  }

  Future<List<SharedFolderCacheRecord>> listCaches({
    SharedFolderCacheRole? role,
    String? ownerMacAddress,
    String? peerMacAddress,
  }) async {
    final db = await _database.database;
    final filters = <String>[];
    final args = <Object?>[];

    if (role != null) {
      filters.add('role = ?');
      args.add(role.name);
    }
    if (ownerMacAddress != null) {
      final normalized = DeviceAliasRepository.normalizeMac(ownerMacAddress);
      if (normalized != null) {
        filters.add('owner_mac_address = ?');
        args.add(normalized);
      }
    }
    if (peerMacAddress != null) {
      final normalized = DeviceAliasRepository.normalizeMac(peerMacAddress);
      if (normalized != null) {
        filters.add('peer_mac_address = ?');
        args.add(normalized);
      }
    }

    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );
    return rows.map(SharedFolderCacheRecord.fromDbMap).toList(growable: false);
  }

  Future<List<SharedFolderIndexEntry>> readIndexEntries(String cacheId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      columns: <String>['index_file_path'],
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return <SharedFolderIndexEntry>[];
    }

    final path = rows.first['index_file_path'] as String?;
    if (path == null || path.isEmpty) {
      return <SharedFolderIndexEntry>[];
    }

    final file = File(path);
    if (!await file.exists()) {
      return <SharedFolderIndexEntry>[];
    }

    final content = await file.readAsString();
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    final rawEntries = (jsonMap['entries'] as List<dynamic>? ?? <dynamic>[]);
    return rawEntries
        .whereType<Map<String, dynamic>>()
        .map(SharedFolderIndexEntry.fromCompactJson)
        .toList(growable: false);
  }

  Future<Uint8List?> readOwnerThumbnailBytes({
    required String cacheId,
    required String thumbnailId,
  }) {
    return _thumbnailCacheService.readOwnerThumbnailBytes(
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );
  }

  Future<String?> resolveReceiverThumbnailPath({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
  }) {
    return _thumbnailCacheService.resolveReceiverThumbnailPath(
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );
  }

  Future<String> saveReceiverThumbnailBytes({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
    required Uint8List bytes,
  }) {
    return _thumbnailCacheService.saveReceiverThumbnailBytes(
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      thumbnailId: thumbnailId,
      bytes: bytes,
    );
  }

  Future<void> deleteCache(String cacheId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      columns: <String>['index_file_path'],
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final path = rows.first['index_file_path'] as String?;
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    await db.delete(
      AppDatabase.sharedFolderCachesTable,
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
    );
  }

  Future<void> _upsertRecord(SharedFolderCacheRecord record) async {
    final db = await _database.database;
    await db.insert(
      AppDatabase.sharedFolderCachesTable,
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _writeIndexFile(
    SharedFolderCacheRecord record,
    List<SharedFolderIndexEntry> entries,
  ) async {
    final file = File(record.indexFilePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    final payload = <String, Object?>{
      'schemaVersion': _schemaVersion,
      'cacheId': record.cacheId,
      'role': record.role.name,
      'ownerMacAddress': record.ownerMacAddress,
      'peerMacAddress': record.peerMacAddress,
      'displayName': record.displayName,
      'rootPath': record.rootPath,
      'updatedAtMs': record.updatedAtMs,
      'entries': entries.map((entry) => entry.toCompactJson()).toList(),
    };

    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<List<SharedFolderIndexEntry>> _indexFolder(
    String rootPath, {
    required String cacheId,
  }) async {
    final root = Directory(rootPath);
    final entries = <SharedFolderIndexEntry>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }

      final relative = p
          .relative(entity.path, from: rootPath)
          .replaceAll('\\', '/');
      final thumbnail = await _thumbnailCacheService.ensureOwnerThumbnail(
        cacheId: cacheId,
        relativePath: relative,
        sourcePath: entity.path,
        sizeBytes: stat.size,
        modifiedAtMs: stat.modified.millisecondsSinceEpoch,
      );

      entries.add(
        SharedFolderIndexEntry(
          relativePath: relative,
          sizeBytes: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
          thumbnailId: thumbnail?.thumbnailId,
        ),
      );
    }

    entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return entries;
  }

  String _resolveDisplayName({
    required String? providedName,
    required String fallbackPath,
  }) {
    final candidate = providedName?.trim() ?? '';
    if (candidate.isNotEmpty) {
      return candidate;
    }
    final normalized = p.normalize(fallbackPath);
    final baseName = p.basename(normalized);
    return baseName.isEmpty ? 'Shared folder' : baseName;
  }

  String _createCacheId({
    required SharedFolderCacheRole role,
    required String ownerMacAddress,
    required String? peerMacAddress,
    required String rootIdentity,
  }) {
    final raw = <String>[
      'v$_schemaVersion',
      role.name,
      ownerMacAddress,
      peerMacAddress ?? '-',
      rootIdentity.replaceAll('\\', '/').trim().toLowerCase(),
    ].join('|');
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'v${_schemaVersion}_$digest';
  }

  String _createCacheFileName({
    required SharedFolderCacheRole role,
    required String displayName,
    required String cacheId,
  }) {
    final sanitized = _sanitizeFileToken(displayName);
    return '${role.name}_${sanitized}_$cacheId.landa-cache.json';
  }

  String _sanitizeFileToken(String input) {
    final normalized = input.trim().toLowerCase();
    final safe = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final collapsed = safe
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (collapsed.isEmpty) {
      return 'folder';
    }
    return collapsed.length > 24 ? collapsed.substring(0, 24) : collapsed;
  }

  String _normalizeOrThrow(String macAddress, {required String field}) {
    final normalized = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalized == null) {
      throw ArgumentError('Invalid $field: $macAddress');
    }
    return normalized;
  }
}
