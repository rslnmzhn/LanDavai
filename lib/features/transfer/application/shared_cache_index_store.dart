import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../core/storage/app_database.dart';
import '../data/shared_folder_cache_repository.dart';
import '../data/thumbnail_cache_service.dart';
import '../domain/shared_folder_cache.dart';

class SharedCacheIndexWriteResult {
  const SharedCacheIndexWriteResult({
    required this.changed,
    required this.itemCount,
    required this.totalBytes,
  });

  final bool changed;
  final int itemCount;
  final int totalBytes;
}

class SharedCacheIndexStore {
  SharedCacheIndexStore({
    required AppDatabase database,
    ThumbnailCacheService? thumbnailCacheService,
  }) : _database = database,
       _thumbnailCacheService =
           thumbnailCacheService ?? ThumbnailCacheService(database: database);

  static const int schemaVersion = 1;

  final AppDatabase _database;
  final ThumbnailCacheService _thumbnailCacheService;

  Future<String> normalizeExistingDirectoryPath(String folderPath) async {
    final directory = Directory(folderPath);
    return _normalizeExistingDirectoryPath(directory);
  }

  Future<String> resolveIndexFilePath({
    required SharedFolderCacheRole role,
    required String displayName,
    required String cacheId,
  }) async {
    final cacheDirectory = await _database.resolveSharedCacheDirectory();
    return p.join(
      cacheDirectory.path,
      _createCacheFileName(
        role: role,
        displayName: displayName,
        cacheId: cacheId,
      ),
    );
  }

  Future<List<SharedFolderIndexEntry>> readIndexEntries(
    SharedFolderCacheRecord record,
  ) {
    return _readIndexEntriesFromPath(record.indexFilePath);
  }

  Future<SharedCacheIndexWriteResult> materializeOwnerFolderIndex({
    required SharedFolderCacheRecord record,
    required String folderPath,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
  }) async {
    final rootDirectory = Directory(folderPath);
    if (!await rootDirectory.exists()) {
      throw ArgumentError('Directory does not exist: $folderPath');
    }

    final normalizedRoot = await _normalizeExistingDirectoryPath(rootDirectory);
    final previousEntries = await _readIndexEntriesFromPath(
      record.indexFilePath,
    );
    Map<String, SharedFolderIndexEntry>? previousEntriesByRelativePath;
    if (previousEntries.isNotEmpty) {
      previousEntriesByRelativePath = <String, SharedFolderIndexEntry>{
        for (final entry in previousEntries) entry.relativePath: entry,
      };
    }

    final entries = await _indexFolder(
      normalizedRoot,
      cacheId: record.cacheId,
      previousEntriesByRelativePath: previousEntriesByRelativePath,
      parallelWorkers: parallelWorkers,
      onProgress: onProgress,
    );
    await _writeIndexFile(record, entries);
    return _buildWriteResult(entries, changed: true);
  }

  Future<SharedCacheIndexWriteResult> materializeOwnerSelectionIndex({
    required SharedFolderCacheRecord record,
    required List<String> filePaths,
  }) async {
    final normalizedPaths =
        filePaths
            .map((path) => p.normalize(File(path).absolute.path))
            .toSet()
            .toList(growable: false)
          ..sort();

    if (normalizedPaths.isEmpty) {
      throw ArgumentError('filePaths must not be empty.');
    }

    final entries = <SharedFolderIndexEntry>[];
    for (var index = 0; index < normalizedPaths.length; index += 1) {
      final absolutePath = normalizedPaths[index];
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
        cacheId: record.cacheId,
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
      if ((index + 1) % 20 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (entries.isEmpty) {
      throw ArgumentError('None of the selected files are accessible.');
    }

    await _writeIndexFile(record, entries);
    return _buildWriteResult(entries, changed: true);
  }

  Future<SharedCacheIndexWriteResult> materializeReceiverIndex({
    required SharedFolderCacheRecord record,
    required List<SharedFolderIndexEntry> entries,
  }) async {
    await _writeIndexFile(record, entries);
    return _buildWriteResult(entries, changed: true);
  }

  Future<SharedCacheIndexWriteResult> refreshOwnerSelectionIndex(
    SharedFolderCacheRecord record, {
    OwnerCacheProgressCallback? onProgress,
  }) async {
    if (!record.rootPath.startsWith('selection://')) {
      final entries = await _readIndexEntriesFromPath(record.indexFilePath);
      return _buildWriteResult(entries, changed: false);
    }

    final entries = await _readIndexEntriesFromPath(record.indexFilePath);
    final normalized = <SharedFolderIndexEntry>[];
    var changed = false;
    final total = entries.length;
    var processed = 0;

    for (final entry in entries) {
      processed += 1;
      final absolutePath = entry.absolutePath;
      if (absolutePath == null || absolutePath.trim().isEmpty) {
        changed = true;
        onProgress?.call(
          processedFiles: processed,
          totalFiles: total,
          relativePath: entry.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        continue;
      }

      final file = File(absolutePath);
      if (!await file.exists()) {
        changed = true;
        onProgress?.call(
          processedFiles: processed,
          totalFiles: total,
          relativePath: entry.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        continue;
      }

      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        changed = true;
        onProgress?.call(
          processedFiles: processed,
          totalFiles: total,
          relativePath: entry.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        continue;
      }

      final sizeBytes = stat.size;
      final modifiedAtMs = stat.modified.millisecondsSinceEpoch;
      String? thumbnailId = entry.thumbnailId;
      if (sizeBytes != entry.sizeBytes || modifiedAtMs != entry.modifiedAtMs) {
        changed = true;
        final thumbnail = await _thumbnailCacheService.ensureOwnerThumbnail(
          cacheId: record.cacheId,
          relativePath: entry.relativePath,
          sourcePath: absolutePath,
          sizeBytes: sizeBytes,
          modifiedAtMs: modifiedAtMs,
        );
        thumbnailId = thumbnail?.thumbnailId;
      }

      normalized.add(
        SharedFolderIndexEntry(
          relativePath: entry.relativePath,
          sizeBytes: sizeBytes,
          modifiedAtMs: modifiedAtMs,
          absolutePath: absolutePath,
          thumbnailId: thumbnailId,
        ),
      );
      onProgress?.call(
        processedFiles: processed,
        totalFiles: total,
        relativePath: entry.relativePath,
        stage: OwnerCacheProgressStage.indexing,
      );
      if (processed % 20 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (changed) {
      await _writeIndexFile(record, normalized);
    }
    return _buildWriteResult(changed ? normalized : entries, changed: changed);
  }

  Future<SharedCacheIndexWriteResult> refreshOwnerFolderSubdirectoryIndex(
    SharedFolderCacheRecord record, {
    required String relativeFolderPath,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
  }) async {
    if (record.rootPath.startsWith('selection://')) {
      final entries = await _readIndexEntriesFromPath(record.indexFilePath);
      return _buildWriteResult(entries, changed: false);
    }

    final normalizedFolder = _normalizeRelativeFolderPath(relativeFolderPath);
    final root = Directory(record.rootPath);
    if (!await root.exists()) {
      throw ArgumentError('Directory does not exist: ${record.rootPath}');
    }

    final existingEntries = await _readIndexEntriesFromPath(
      record.indexFilePath,
    );
    final untouched = <SharedFolderIndexEntry>[];
    final previousScoped = <String, SharedFolderIndexEntry>{};
    for (final entry in existingEntries) {
      if (_isRelativePathWithinFolder(entry.relativePath, normalizedFolder)) {
        previousScoped[entry.relativePath] = entry;
      } else {
        untouched.add(entry);
      }
    }

    final scopedRootPath = p.join(record.rootPath, normalizedFolder);
    final scopedRoot = Directory(scopedRootPath);
    var refreshedScopedEntries = const <SharedFolderIndexEntry>[];
    if (await scopedRoot.exists()) {
      refreshedScopedEntries = await _indexFolder(
        scopedRootPath,
        cacheId: record.cacheId,
        previousEntriesByRelativePath: previousScoped,
        parallelWorkers: parallelWorkers,
        onProgress: onProgress,
        relativePrefix: normalizedFolder,
      );
    }

    final merged = <SharedFolderIndexEntry>[
      ...untouched,
      ...refreshedScopedEntries,
    ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));

    await _writeIndexFile(record, merged);
    return _buildWriteResult(merged, changed: true);
  }

  Future<void> deleteIndexArtifacts(SharedFolderCacheRecord record) async {
    if (record.indexFilePath.isNotEmpty) {
      final file = File(record.indexFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (record.role == SharedFolderCacheRole.owner) {
      await _thumbnailCacheService.deleteOwnerCacheThumbnails(record.cacheId);
      return;
    }

    final ownerMacAddress = record.ownerMacAddress.trim();
    if (record.role == SharedFolderCacheRole.receiver &&
        ownerMacAddress.isNotEmpty) {
      await _thumbnailCacheService.deleteReceiverCacheThumbnails(
        ownerMacAddress: ownerMacAddress,
        cacheId: record.cacheId,
      );
    }
  }

  SharedCacheIndexWriteResult _buildWriteResult(
    List<SharedFolderIndexEntry> entries, {
    required bool changed,
  }) {
    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );
    return SharedCacheIndexWriteResult(
      changed: changed,
      itemCount: entries.length,
      totalBytes: totalBytes,
    );
  }

  Future<List<SharedFolderIndexEntry>> _readIndexEntriesFromPath(
    String indexFilePath,
  ) async {
    if (indexFilePath.trim().isEmpty) {
      return <SharedFolderIndexEntry>[];
    }

    final file = File(indexFilePath);
    if (!await file.exists()) {
      return <SharedFolderIndexEntry>[];
    }

    final content = await file.readAsString();
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    final rawEntries = jsonMap['entries'] as List<dynamic>? ?? <dynamic>[];
    return rawEntries
        .whereType<Map<String, dynamic>>()
        .map(SharedFolderIndexEntry.fromCompactJson)
        .toList(growable: false);
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
      'schemaVersion': schemaVersion,
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
    Map<String, SharedFolderIndexEntry>? previousEntriesByRelativePath,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
    String relativePrefix = '',
  }) async {
    final root = Directory(rootPath);
    final normalizedPrefix = _normalizeRelativeFolderPath(relativePrefix);
    final probes = <_FolderProbeEntry>[];
    var discoveredFiles = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }
      final relativePath = p
          .relative(entity.path, from: rootPath)
          .replaceAll('\\', '/');
      final cacheRelativePath = normalizedPrefix.isEmpty
          ? relativePath
          : '$normalizedPrefix/$relativePath';
      probes.add(
        _FolderProbeEntry(
          sourcePath: entity.path,
          relativePath: cacheRelativePath,
          sizeBytes: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
        ),
      );
      final reportedPath = probes.last.relativePath;
      discoveredFiles += 1;
      if (discoveredFiles == 1 || discoveredFiles % 32 == 0) {
        onProgress?.call(
          processedFiles: discoveredFiles,
          totalFiles: 0,
          relativePath: reportedPath,
          stage: OwnerCacheProgressStage.scanning,
        );
      }
      if (discoveredFiles % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (discoveredFiles > 0 && discoveredFiles % 32 != 0) {
      final relativePath = probes.last.relativePath;
      onProgress?.call(
        processedFiles: discoveredFiles,
        totalFiles: 0,
        relativePath: relativePath,
        stage: OwnerCacheProgressStage.scanning,
      );
    }

    final total = probes.length;
    if (total == 0) {
      return <SharedFolderIndexEntry>[];
    }

    final entries = List<SharedFolderIndexEntry?>.filled(
      total,
      null,
      growable: false,
    );
    final workerCount = _resolveParallelWorkerCount(
      total,
      overrideWorkers: parallelWorkers,
    );
    var nextIndex = 0;
    var processedCount = 0;

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        if (index >= total) {
          return;
        }
        nextIndex += 1;

        final probe = probes[index];
        final previous = previousEntriesByRelativePath?[probe.relativePath];
        if (previous != null &&
            previous.sizeBytes == probe.sizeBytes &&
            previous.modifiedAtMs == probe.modifiedAtMs) {
          entries[index] = previous;
        } else {
          final thumbnail = await _thumbnailCacheService.ensureOwnerThumbnail(
            cacheId: cacheId,
            relativePath: probe.relativePath,
            sourcePath: probe.sourcePath,
            sizeBytes: probe.sizeBytes,
            modifiedAtMs: probe.modifiedAtMs,
          );
          entries[index] = SharedFolderIndexEntry(
            relativePath: probe.relativePath,
            sizeBytes: probe.sizeBytes,
            modifiedAtMs: probe.modifiedAtMs,
            thumbnailId: thumbnail?.thumbnailId,
          );
        }

        processedCount += 1;
        onProgress?.call(
          processedFiles: processedCount,
          totalFiles: total,
          relativePath: probe.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        if (processedCount % 20 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => runWorker()),
    );

    final completedEntries = entries.whereType<SharedFolderIndexEntry>().toList(
      growable: false,
    );

    if (completedEntries.length != total) {
      throw StateError(
        'Folder indexing did not complete for all files '
        '($total expected, ${completedEntries.length} collected).',
      );
    }

    final sortedEntries = List<SharedFolderIndexEntry>.from(completedEntries);
    sortedEntries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return sortedEntries;
  }

  String _normalizeRelativeFolderPath(String value) {
    return value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }

  bool _isRelativePathWithinFolder(String relativePath, String folderPath) {
    final normalizedRelative = _normalizeRelativeFolderPath(relativePath);
    final normalizedFolder = _normalizeRelativeFolderPath(folderPath);
    if (normalizedFolder.isEmpty) {
      return true;
    }
    return normalizedRelative == normalizedFolder ||
        normalizedRelative.startsWith('$normalizedFolder/');
  }

  int _resolveParallelWorkerCount(int totalFiles, {int? overrideWorkers}) {
    if (totalFiles <= 1) {
      return 1;
    }
    if (overrideWorkers != null && overrideWorkers > 0) {
      final capped = math.max(
        1,
        math.min(overrideWorkers, Platform.numberOfProcessors),
      );
      return math.min(totalFiles, capped);
    }
    final availableWorkers = math.max(2, Platform.numberOfProcessors - 1);
    return math.min(totalFiles, availableWorkers);
  }

  Future<String> _normalizeExistingDirectoryPath(Directory directory) async {
    try {
      final resolved = await directory.resolveSymbolicLinks();
      return p.normalize(resolved);
    } catch (_) {
      return p.normalize(directory.absolute.path);
    }
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
}

class _FolderProbeEntry {
  const _FolderProbeEntry({
    required this.sourcePath,
    required this.relativePath,
    required this.sizeBytes,
    required this.modifiedAtMs,
  });

  final String sourcePath;
  final String relativePath;
  final int sizeBytes;
  final int modifiedAtMs;
}
