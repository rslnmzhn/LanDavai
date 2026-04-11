import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../files/application/file_explorer_contract.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_packet_codec.dart';
import '../data/lan_protocol_events.dart';
import '../domain/discovered_device.dart';

class RemoteShareOption {
  const RemoteShareOption({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entry,
    this.receiverCacheSnapshot,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final SharedCatalogEntryItem entry;
  final SharedFolderCacheRecord? receiverCacheSnapshot;

  bool get hasReceiverCacheSnapshot => receiverCacheSnapshot != null;
}

class RemoteBrowseStartResult {
  const RemoteBrowseStartResult({
    required this.hadTargets,
    required this.optionCount,
  });

  final bool hadTargets;
  final int optionCount;
}

class RemoteBrowsePreviewPathUpdate {
  const RemoteBrowsePreviewPathUpdate({
    required this.ownerIp,
    required this.cacheId,
    required this.relativePath,
    required this.previewPath,
  });

  final String ownerIp;
  final String cacheId;
  final String relativePath;
  final String previewPath;
}

class RemoteBrowseProjection {
  const RemoteBrowseProjection({required this.options, required this.owners});

  final List<RemoteShareOption> options;
  final List<RemoteBrowseOwnerChoice> owners;
}

class RemoteBrowseOwnerChoice {
  const RemoteBrowseOwnerChoice({
    required this.ip,
    required this.name,
    required this.macAddress,
    required this.shareCount,
    required this.fileCount,
    required this.cachedShareCount,
  });

  final String ip;
  final String name;
  final String macAddress;
  final int shareCount;
  final int fileCount;
  final int cachedShareCount;
}

class RemoteBrowseFolderChoice {
  const RemoteBrowseFolderChoice({
    required this.ownerIp,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.folderPath,
    required this.fileCount,
    required this.totalBytes,
  });

  final String ownerIp;
  final String cacheId;
  final String cacheDisplayName;
  final String folderPath;
  final int fileCount;
  final int totalBytes;

  String get id => '$ownerIp|$cacheId|$folderPath';

  int get depth =>
      folderPath.isEmpty ? 0 : '/'.allMatches(folderPath).length + 1;

  String get displayLabel => folderPath.isEmpty
      ? '$cacheDisplayName (вся расшаренная папка)'
      : '$cacheDisplayName / $folderPath';
}

class RemoteBrowseExplorerDirectory {
  const RemoteBrowseExplorerDirectory({
    required this.entries,
    required this.totalFiles,
    required this.totalFolders,
    required this.hiddenFilesCount,
    required this.isFileListCapped,
  });

  final FileExplorerVirtualDirectory entries;
  final int totalFiles;
  final int totalFolders;
  final int hiddenFilesCount;
  final bool isFileListCapped;
}

enum RemoteBrowseExplorerViewMode { structured, flat }

enum RemoteBrowseMediaKind { image, video, other }

enum RemoteBrowseFlatFileCategory { images, videos, music, documents, programs }

class RemoteBrowseFileChoice {
  const RemoteBrowseFileChoice({
    required this.ownerIp,
    required this.ownerName,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.relativePath,
    required this.sizeBytes,
    this.thumbnailId,
    this.previewPath,
    this.hasReceiverCacheSnapshot = false,
  });

  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
  };

  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.webm',
    '.m4v',
    '.3gp',
    '.mpeg',
    '.mpg',
  };

  final String ownerIp;
  final String ownerName;
  final String cacheId;
  final String cacheDisplayName;
  final String relativePath;
  final int sizeBytes;
  final String? thumbnailId;
  final String? previewPath;
  final bool hasReceiverCacheSnapshot;

  String get id => '$ownerIp|$cacheId|$relativePath';

  RemoteBrowseMediaKind get mediaKind {
    if (_imageExtensions.contains(extension)) {
      return RemoteBrowseMediaKind.image;
    }
    if (_videoExtensions.contains(extension)) {
      return RemoteBrowseMediaKind.video;
    }
    return RemoteBrowseMediaKind.other;
  }

  String get extension => p.extension(relativePath).toLowerCase();

  String get previewLabel {
    final ext = extension;
    if (ext.isNotEmpty) {
      return ext.substring(1).toUpperCase();
    }
    switch (mediaKind) {
      case RemoteBrowseMediaKind.image:
        return 'IMG';
      case RemoteBrowseMediaKind.video:
        return 'VID';
      case RemoteBrowseMediaKind.other:
        return 'FILE';
    }
  }
}

class RemoteBrowseResolvedFile {
  const RemoteBrowseResolvedFile({
    required this.token,
    required this.ownerIp,
    required this.ownerName,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.relativePath,
    required this.displayPath,
    required this.sizeBytes,
    required this.mediaKind,
    required this.previewLabel,
    this.previewPath,
    this.thumbnailId,
    this.hasReceiverCacheSnapshot = false,
  });

  final String token;
  final String ownerIp;
  final String ownerName;
  final String cacheId;
  final String cacheDisplayName;
  final String relativePath;
  final String displayPath;
  final int sizeBytes;
  final RemoteBrowseMediaKind mediaKind;
  final String previewLabel;
  final String? previewPath;
  final String? thumbnailId;
  final bool hasReceiverCacheSnapshot;
}

class RemoteShareBrowser extends ChangeNotifier {
  RemoteShareBrowser({
    required SharedCacheCatalog sharedCacheCatalog,
    this.maxFilesPerCacheForUi = 4000,
    this.maxVisibleFiles = 2500,
  }) : _sharedCacheCatalog = sharedCacheCatalog;

  static const String allDevicesFilterKey = '__all_devices__';

  final SharedCacheCatalog _sharedCacheCatalog;
  final int maxFilesPerCacheForUi;
  final int maxVisibleFiles;

  final List<RemoteShareOption> _options = <RemoteShareOption>[];
  final Map<String, String> _previewPathsByFileKey = <String, String>{};
  final Map<String, SharedFolderCacheRecord> _receiverSnapshotsByRemoteCacheId =
      <String, SharedFolderCacheRecord>{};

  bool _isLoading = false;
  String? _activeRequestId;
  String? _receiverMacAddress;

  bool get isLoading => _isLoading;

  RemoteBrowseProjection get currentBrowseProjection {
    return RemoteBrowseProjection(
      options: List<RemoteShareOption>.unmodifiable(_options),
      owners: _buildOwnerChoices(),
    );
  }

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
    _activeRequestId = requestId;
    _receiverMacAddress = DeviceAliasRepository.normalizeMac(
      receiverMacAddress,
    );
    _options.clear();
    _previewPathsByFileKey.clear();
    await _refreshReceiverSnapshots();
    if (targets.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return const RemoteBrowseStartResult(hadTargets: false, optionCount: 0);
    }

    _isLoading = true;
    notifyListeners();
    try {
      for (final target in targets) {
        await sendShareQuery(
          targetIp: target.ip,
          requestId: requestId,
          requesterName: requesterName,
        );
      }
      await Future<void>.delayed(responseWindow);
      return RemoteBrowseStartResult(
        hadTargets: true,
        optionCount: _options.length,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> applyRemoteCatalog({
    required ShareCatalogEvent event,
    required String ownerDisplayName,
    required String ownerMacAddress,
  }) async {
    if (_activeRequestId != null && event.requestId != _activeRequestId) {
      return;
    }

    final normalizedOwnerMac =
        DeviceAliasRepository.normalizeMac(ownerMacAddress) ?? ownerMacAddress;
    await _refreshReceiverSnapshots(ownerMacAddress: normalizedOwnerMac);

    _options.removeWhere((option) => option.ownerIp == event.ownerIp);
    _clearOwnerPreviewPaths(ownerIp: event.ownerIp, notify: false);

    for (final entry in event.entries) {
      final uiEntry = _trimRemoteShareEntryForProjection(entry);
      _options.add(
        RemoteShareOption(
          requestId: event.requestId,
          ownerIp: event.ownerIp,
          ownerName: ownerDisplayName,
          ownerMacAddress: normalizedOwnerMac,
          entry: uiEntry,
          receiverCacheSnapshot:
              _receiverSnapshotsByRemoteCacheId[entry.cacheId],
        ),
      );
    }

    _options.sort((a, b) {
      final ownerCmp = a.ownerName.toLowerCase().compareTo(
        b.ownerName.toLowerCase(),
      );
      if (ownerCmp != 0) {
        return ownerCmp;
      }
      return a.entry.displayName.toLowerCase().compareTo(
        b.entry.displayName.toLowerCase(),
      );
    });
    notifyListeners();
  }

  RemoteBrowseExplorerDirectory buildExplorerDirectory({
    required String filterKey,
    required String folderPath,
    required RemoteBrowseExplorerViewMode viewMode,
    Set<RemoteBrowseFlatFileCategory>? visibleFlatCategories,
    bool showAllFlatCategories = true,
  }) {
    if (viewMode == RemoteBrowseExplorerViewMode.flat) {
      return _buildFlatExplorerDirectory(
        filterKey: filterKey,
        visibleCategories: visibleFlatCategories,
        showAllCategories: showAllFlatCategories,
      );
    }
    final ownerIp = filterKey == allDevicesFilterKey ? null : filterKey;
    if (ownerIp == null) {
      return _buildStructuredAggregatedExplorerDirectory(
        folderPath: folderPath,
      );
    }
    return _buildOwnerExplorerDirectory(
      ownerIp: ownerIp,
      folderPath: folderPath,
    );
  }

  String rootLabelForFilter(String filterKey) {
    if (filterKey == allDevicesFilterKey) {
      return 'Все устройства';
    }
    return ownerChoiceForIp(filterKey)?.name ?? filterKey;
  }

  RemoteBrowseOwnerChoice? ownerChoiceForIp(String ownerIp) {
    final owners = _buildOwnerChoices();
    for (final owner in owners) {
      if (owner.ip == ownerIp) {
        return owner;
      }
    }
    return null;
  }

  RemoteBrowseResolvedFile? resolveFileToken(String token) {
    for (final option in _options) {
      final entry = option.entry;
      for (final file in entry.files) {
        final resolved = _toResolvedFile(
          option: option,
          file: file,
          includeSourceInPath: false,
        );
        if (resolved.token == token) {
          return resolved;
        }
      }
    }
    return null;
  }

  bool containsFileToken(String token) => resolveFileToken(token) != null;

  Set<String> currentFileTokens() {
    final tokens = <String>{};
    for (final option in _options) {
      final entry = option.entry;
      for (final file in entry.files) {
        tokens.add(
          _fileToken(
            ownerIp: option.ownerIp,
            cacheId: entry.cacheId,
            relativePath: file.relativePath,
          ),
        );
      }
    }
    return tokens;
  }

  String? ownerMacForCache({required String ownerIp, required String cacheId}) {
    for (final option in _options) {
      if (option.ownerIp != ownerIp || option.entry.cacheId != cacheId) {
        continue;
      }
      return DeviceAliasRepository.normalizeMac(option.ownerMacAddress);
    }
    return null;
  }

  String? previewPathFor({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
  }) {
    return _previewPathsByFileKey[_previewKey(
      ownerIp: ownerIp,
      cacheId: cacheId,
      relativePath: relativePath,
    )];
  }

  bool hasPreviewPath({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
  }) {
    return previewPathFor(
          ownerIp: ownerIp,
          cacheId: cacheId,
          relativePath: relativePath,
        ) !=
        null;
  }

  void recordPreviewPath({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
    required String previewPath,
    bool notify = true,
  }) {
    final changed = _recordPreviewPathValue(
      ownerIp: ownerIp,
      cacheId: cacheId,
      relativePath: relativePath,
      previewPath: previewPath,
    );
    if (notify && changed) {
      notifyListeners();
    }
  }

  void recordPreviewPaths(
    Iterable<RemoteBrowsePreviewPathUpdate> updates, {
    bool notify = true,
  }) {
    var changed = false;
    for (final update in updates) {
      changed =
          _recordPreviewPathValue(
            ownerIp: update.ownerIp,
            cacheId: update.cacheId,
            relativePath: update.relativePath,
            previewPath: update.previewPath,
          ) ||
          changed;
    }
    if (notify && changed) {
      notifyListeners();
    }
  }

  void clearOwnerPreviewPaths({required String ownerIp}) {
    _clearOwnerPreviewPaths(ownerIp: ownerIp, notify: true);
  }

  Future<void> _refreshReceiverSnapshots({String? ownerMacAddress}) async {
    final receiverMac = _receiverMacAddress;
    if (receiverMac == null || receiverMac.isEmpty) {
      _receiverSnapshotsByRemoteCacheId.clear();
      return;
    }

    final snapshots = await _sharedCacheCatalog.listReceiverCaches(
      receiverMacAddress: receiverMac,
      ownerMacAddress: ownerMacAddress,
    );
    if (ownerMacAddress == null) {
      _receiverSnapshotsByRemoteCacheId
        ..clear()
        ..addEntries(
          snapshots
              .where((cache) => cache.rootPath.trim().isNotEmpty)
              .map(
                (cache) => MapEntry<String, SharedFolderCacheRecord>(
                  cache.rootPath.trim(),
                  cache,
                ),
              ),
        );
      return;
    }

    final normalizedOwnerMac =
        DeviceAliasRepository.normalizeMac(ownerMacAddress) ?? ownerMacAddress;
    _receiverSnapshotsByRemoteCacheId.removeWhere((_, snapshot) {
      final snapshotOwner =
          DeviceAliasRepository.normalizeMac(snapshot.ownerMacAddress) ??
          snapshot.ownerMacAddress;
      return snapshotOwner == normalizedOwnerMac;
    });
    for (final snapshot in snapshots) {
      final remoteCacheId = snapshot.rootPath.trim();
      if (remoteCacheId.isEmpty) {
        continue;
      }
      _receiverSnapshotsByRemoteCacheId[remoteCacheId] = snapshot;
    }
  }

  void _clearOwnerPreviewPaths({
    required String ownerIp,
    required bool notify,
  }) {
    final removed = <String>[];
    for (final key in _previewPathsByFileKey.keys) {
      if (key.startsWith('$ownerIp|')) {
        removed.add(key);
      }
    }
    if (removed.isEmpty) {
      return;
    }
    for (final key in removed) {
      _previewPathsByFileKey.remove(key);
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool _recordPreviewPathValue({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
    required String previewPath,
  }) {
    final normalizedPath = previewPath.trim();
    if (normalizedPath.isEmpty) {
      return false;
    }
    final key = _previewKey(
      ownerIp: ownerIp,
      cacheId: cacheId,
      relativePath: relativePath,
    );
    if (_previewPathsByFileKey[key] == normalizedPath) {
      return false;
    }
    _previewPathsByFileKey[key] = normalizedPath;
    return true;
  }

  List<RemoteBrowseOwnerChoice> _buildOwnerChoices() {
    final ownersByIp = <String, _RemoteOwnerDraft>{};
    for (final option in _options) {
      final draft = ownersByIp.putIfAbsent(
        option.ownerIp,
        () => _RemoteOwnerDraft(
          ip: option.ownerIp,
          name: option.ownerName,
          macAddress: option.ownerMacAddress,
        ),
      );
      draft.shareCount += 1;
      draft.fileCount += option.entry.itemCount;
      if (option.hasReceiverCacheSnapshot) {
        draft.cachedShareCount += 1;
      }
    }

    final list = ownersByIp.values
        .map(
          (draft) => RemoteBrowseOwnerChoice(
            ip: draft.ip,
            name: draft.name,
            macAddress: draft.macAddress,
            shareCount: draft.shareCount,
            fileCount: draft.fileCount,
            cachedShareCount: draft.cachedShareCount,
          ),
        )
        .toList(growable: false);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  RemoteBrowseExplorerDirectory _buildFlatExplorerDirectory({
    required String filterKey,
    required Set<RemoteBrowseFlatFileCategory>? visibleCategories,
    required bool showAllCategories,
  }) {
    final files = <RemoteBrowseResolvedFile>[];
    for (final option in _options) {
      if (filterKey != allDevicesFilterKey && option.ownerIp != filterKey) {
        continue;
      }
      for (final file in option.entry.files) {
        if (files.length >= maxVisibleFiles) {
          break;
        }
        files.add(
          _toResolvedFile(
            option: option,
            file: file,
            includeSourceInPath: true,
          ),
        );
      }
      if (files.length >= maxVisibleFiles) {
        break;
      }
    }
    files.removeWhere((file) {
      if (showAllCategories) {
        return false;
      }
      final categories = visibleCategories;
      if (categories == null || categories.isEmpty) {
        return true;
      }
      return !categories.contains(
        flatCategoryForRelativePath(file.relativePath),
      );
    });
    files.sort(_compareFlatResolvedFiles);
    final entries = files
        .map(
          (file) => FileExplorerVirtualFile(
            path: 'remote://${file.token}',
            virtualPath: file.relativePath,
            sourceToken: file.token,
            subtitle:
                '${file.ownerName} • ${file.cacheDisplayName} • ${_formatBytes(file.sizeBytes)}',
            sizeBytes: file.sizeBytes,
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
            changedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList(growable: false);
    final totalFiles = _countFiles(filterKey: filterKey);
    final hiddenFilesCount = totalFiles > files.length
        ? totalFiles - files.length
        : 0;
    return RemoteBrowseExplorerDirectory(
      entries: FileExplorerVirtualDirectory(files: entries),
      totalFiles: totalFiles,
      totalFolders: 0,
      hiddenFilesCount: hiddenFilesCount,
      isFileListCapped: hiddenFilesCount > 0,
    );
  }

  RemoteBrowseExplorerDirectory _buildStructuredAggregatedExplorerDirectory({
    required String folderPath,
  }) {
    final normalizedFolder = _normalizeRelativePath(folderPath);
    final folders = <String, FileExplorerVirtualFolder>{};
    final files = <FileExplorerVirtualFile>[];
    var visibleFiles = 0;
    final totalFiles = _countFiles(filterKey: allDevicesFilterKey);

    for (final option in _options) {
      final deviceFolderName = _deviceFolderName(option);
      final shareFolderName = _shareFolderName(option.entry);
      for (final file in option.entry.files) {
        if (visibleFiles >= maxVisibleFiles) {
          continue;
        }
        final normalizedRelativePath = _normalizeRelativePath(
          file.relativePath,
        );
        final browserPath = normalizedRelativePath.isEmpty
            ? '$deviceFolderName/$shareFolderName'
            : '$deviceFolderName/$shareFolderName/$normalizedRelativePath';
        final rest = _relativeRestForFolder(
          folder: normalizedFolder,
          targetPath: browserPath,
        );
        if (rest == null || rest.isEmpty) {
          continue;
        }
        final slashIndex = rest.indexOf('/');
        if (slashIndex != -1) {
          final nextFolder = rest.substring(0, slashIndex);
          final nextFolderPath = normalizedFolder.isEmpty
              ? nextFolder
              : '$normalizedFolder/$nextFolder';
          folders.putIfAbsent(
            nextFolderPath,
            () => FileExplorerVirtualFolder(
              name: nextFolder,
              folderPath: nextFolderPath,
            ),
          );
          continue;
        }
        final resolved = _toResolvedFile(
          option: option,
          file: file,
          includeSourceInPath: false,
        );
        files.add(
          FileExplorerVirtualFile(
            path: 'remote://${resolved.token}',
            virtualPath: browserPath,
            sourceToken: resolved.token,
            subtitle:
                '${option.ownerName} • ${option.entry.displayName} • ${_formatBytes(file.sizeBytes)}',
            sizeBytes: file.sizeBytes,
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
            changedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
        visibleFiles += 1;
      }
    }

    final sortedFolders = folders.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    files.sort(
      (a, b) =>
          a.virtualPath.toLowerCase().compareTo(b.virtualPath.toLowerCase()),
    );
    final hiddenFilesCount = totalFiles > visibleFiles
        ? totalFiles - visibleFiles
        : 0;
    return RemoteBrowseExplorerDirectory(
      entries: FileExplorerVirtualDirectory(
        folders: sortedFolders,
        files: files,
      ),
      totalFiles: totalFiles,
      totalFolders: sortedFolders.length,
      hiddenFilesCount: hiddenFilesCount,
      isFileListCapped: hiddenFilesCount > 0,
    );
  }

  RemoteBrowseExplorerDirectory _buildOwnerExplorerDirectory({
    required String ownerIp,
    required String folderPath,
  }) {
    final normalizedFolder = _normalizeRelativePath(folderPath);
    final folders = <String, FileExplorerVirtualFolder>{};
    final files = <FileExplorerVirtualFile>[];
    var visibleFiles = 0;
    var totalFiles = 0;
    for (final option in _options) {
      if (option.ownerIp != ownerIp) {
        continue;
      }
      final shareFolderName = _shareFolderName(option.entry);
      for (final file in option.entry.files) {
        totalFiles += 1;
        if (visibleFiles >= maxVisibleFiles) {
          continue;
        }
        final normalizedRelativePath = _normalizeRelativePath(
          file.relativePath,
        );
        final browserPath = normalizedRelativePath.isEmpty
            ? shareFolderName
            : '$shareFolderName/$normalizedRelativePath';
        final rest = _relativeRestForFolder(
          folder: normalizedFolder,
          targetPath: browserPath,
        );
        if (rest == null || rest.isEmpty) {
          continue;
        }
        final slashIndex = rest.indexOf('/');
        if (slashIndex != -1) {
          final nextFolder = rest.substring(0, slashIndex);
          final nextFolderPath = normalizedFolder.isEmpty
              ? nextFolder
              : '$normalizedFolder/$nextFolder';
          folders.putIfAbsent(
            nextFolderPath,
            () => FileExplorerVirtualFolder(
              name: nextFolder,
              folderPath: nextFolderPath,
            ),
          );
          continue;
        }
        final resolved = _toResolvedFile(
          option: option,
          file: file,
          includeSourceInPath: false,
        );
        files.add(
          FileExplorerVirtualFile(
            path: 'remote://${resolved.token}',
            virtualPath: browserPath,
            sourceToken: resolved.token,
            subtitle:
                '${option.entry.displayName} • ${_formatBytes(file.sizeBytes)}',
            sizeBytes: file.sizeBytes,
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
            changedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
        visibleFiles += 1;
      }
    }

    final sortedFolders = folders.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    files.sort(
      (a, b) =>
          a.virtualPath.toLowerCase().compareTo(b.virtualPath.toLowerCase()),
    );
    final hiddenFilesCount = totalFiles > visibleFiles
        ? totalFiles - visibleFiles
        : 0;
    return RemoteBrowseExplorerDirectory(
      entries: FileExplorerVirtualDirectory(
        folders: sortedFolders,
        files: files,
      ),
      totalFiles: totalFiles,
      totalFolders: sortedFolders.length,
      hiddenFilesCount: hiddenFilesCount,
      isFileListCapped: hiddenFilesCount > 0,
    );
  }

  SharedCatalogEntryItem _trimRemoteShareEntryForProjection(
    SharedCatalogEntryItem entry,
  ) {
    if (entry.files.length <= maxFilesPerCacheForUi) {
      return entry;
    }
    return SharedCatalogEntryItem(
      cacheId: entry.cacheId,
      displayName: entry.displayName,
      itemCount: entry.itemCount,
      totalBytes: entry.totalBytes,
      files: entry.files.take(maxFilesPerCacheForUi).toList(growable: false),
    );
  }

  RemoteBrowseResolvedFile _toResolvedFile({
    required RemoteShareOption option,
    required SharedCatalogFileItem file,
    required bool includeSourceInPath,
  }) {
    final normalizedRelativePath = _normalizeRelativePath(file.relativePath);
    final displayPath = includeSourceInPath
        ? '${option.ownerName} (${option.ownerIp})/${option.entry.displayName}/$normalizedRelativePath'
        : normalizedRelativePath;
    return RemoteBrowseResolvedFile(
      token: _fileToken(
        ownerIp: option.ownerIp,
        cacheId: option.entry.cacheId,
        relativePath: file.relativePath,
      ),
      ownerIp: option.ownerIp,
      ownerName: option.ownerName,
      cacheId: option.entry.cacheId,
      cacheDisplayName: option.entry.displayName,
      relativePath: normalizedRelativePath,
      displayPath: displayPath,
      sizeBytes: file.sizeBytes,
      mediaKind: _mediaKindForRelativePath(file.relativePath),
      previewLabel: _previewLabelForRelativePath(file.relativePath),
      previewPath: previewPathFor(
        ownerIp: option.ownerIp,
        cacheId: option.entry.cacheId,
        relativePath: file.relativePath,
      ),
      thumbnailId: file.thumbnailId,
      hasReceiverCacheSnapshot: option.hasReceiverCacheSnapshot,
    );
  }

  int _compareResolvedFiles(
    RemoteBrowseResolvedFile a,
    RemoteBrowseResolvedFile b,
  ) {
    final ownerCmp = a.ownerName.toLowerCase().compareTo(
      b.ownerName.toLowerCase(),
    );
    if (ownerCmp != 0) {
      return ownerCmp;
    }
    final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
      b.cacheDisplayName.toLowerCase(),
    );
    if (cacheCmp != 0) {
      return cacheCmp;
    }
    return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
  }

  int _compareFlatResolvedFiles(
    RemoteBrowseResolvedFile a,
    RemoteBrowseResolvedFile b,
  ) {
    final categoryCmp = _flatCategoryRank(a).compareTo(_flatCategoryRank(b));
    if (categoryCmp != 0) {
      return categoryCmp;
    }
    final typeCmp = a.previewLabel.compareTo(b.previewLabel);
    if (typeCmp != 0) {
      return typeCmp;
    }
    return _compareResolvedFiles(a, b);
  }

  int _countFiles({required String filterKey}) {
    var total = 0;
    for (final option in _options) {
      if (filterKey != allDevicesFilterKey && option.ownerIp != filterKey) {
        continue;
      }
      total += option.entry.files.length;
    }
    return total;
  }

  String _deviceFolderName(RemoteShareOption option) {
    return '${option.ownerName} (${option.ownerIp})';
  }

  String _shareFolderName(SharedCatalogEntryItem entry) {
    final trimmed = entry.displayName.trim();
    if (trimmed.isEmpty) {
      return 'Share ${entry.cacheId.substring(0, 6)}';
    }
    return '$trimmed · ${entry.cacheId.substring(0, 6)}';
  }

  String _fileToken({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
  }) {
    return '$ownerIp|$cacheId|${_normalizeRelativePath(relativePath).toLowerCase()}';
  }

  String _previewKey({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
  }) {
    final normalizedPath = relativePath.replaceAll('\\', '/').toLowerCase();
    return '$ownerIp|$cacheId|$normalizedPath';
  }

  String _normalizeRelativePath(String value) {
    return value.replaceAll('\\', '/').trim();
  }

  String? _relativeRestForFolder({
    required String folder,
    required String targetPath,
  }) {
    if (folder.isEmpty) {
      return targetPath;
    }
    if (targetPath == folder) {
      return '';
    }
    if (!targetPath.startsWith('$folder/')) {
      return null;
    }
    return targetPath.substring(folder.length + 1);
  }

  RemoteBrowseMediaKind _mediaKindForRelativePath(String relativePath) {
    final extension = p.extension(relativePath).toLowerCase();
    if (RemoteBrowseFileChoice._imageExtensions.contains(extension)) {
      return RemoteBrowseMediaKind.image;
    }
    if (RemoteBrowseFileChoice._videoExtensions.contains(extension)) {
      return RemoteBrowseMediaKind.video;
    }
    return RemoteBrowseMediaKind.other;
  }

  int _flatCategoryRank(RemoteBrowseResolvedFile file) {
    switch (flatCategoryForRelativePath(file.relativePath)) {
      case RemoteBrowseFlatFileCategory.images:
      case RemoteBrowseFlatFileCategory.videos:
      case RemoteBrowseFlatFileCategory.music:
        return 0;
      case RemoteBrowseFlatFileCategory.documents:
        return 1;
      case RemoteBrowseFlatFileCategory.programs:
        return 2;
    }
  }

  RemoteBrowseFlatFileCategory flatCategoryForRelativePath(
    String relativePath,
  ) {
    final extension = p.extension(relativePath).toLowerCase();
    if (RemoteBrowseFileChoice._imageExtensions.contains(extension)) {
      return RemoteBrowseFlatFileCategory.images;
    }
    if (RemoteBrowseFileChoice._videoExtensions.contains(extension)) {
      return RemoteBrowseFlatFileCategory.videos;
    }
    if (_audioExtensions.contains(extension)) {
      return RemoteBrowseFlatFileCategory.music;
    }
    if (_documentExtensions.contains(extension)) {
      return RemoteBrowseFlatFileCategory.documents;
    }
    if (_programExtensions.contains(extension)) {
      return RemoteBrowseFlatFileCategory.programs;
    }
    return RemoteBrowseFlatFileCategory.programs;
  }

  String flatCategoryLabel(RemoteBrowseFlatFileCategory category) {
    switch (category) {
      case RemoteBrowseFlatFileCategory.images:
        return 'Показывать картинки';
      case RemoteBrowseFlatFileCategory.videos:
        return 'Показывать видео';
      case RemoteBrowseFlatFileCategory.music:
        return 'Показывать музыку';
      case RemoteBrowseFlatFileCategory.documents:
        return 'Показывать документы';
      case RemoteBrowseFlatFileCategory.programs:
        return 'Показывать программные файлы';
    }
  }

  String _previewLabelForRelativePath(String relativePath) {
    final extension = p.extension(relativePath).toLowerCase();
    if (extension.isNotEmpty) {
      return extension.substring(1).toUpperCase();
    }
    switch (_mediaKindForRelativePath(relativePath)) {
      case RemoteBrowseMediaKind.image:
        return 'IMG';
      case RemoteBrowseMediaKind.video:
        return 'VID';
      case RemoteBrowseMediaKind.other:
        return 'FILE';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  static const Set<String> _audioExtensions = <String>{
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
  };

  static const Set<String> _documentExtensions = <String>{
    '.pdf',
    '.doc',
    '.docx',
    '.txt',
    '.md',
    '.csv',
    '.rtf',
    '.odt',
    '.pages',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.ods',
    '.odp',
    '.epub',
  };

  static const Set<String> _programExtensions = <String>{
    '',
    '.dart',
    '.kt',
    '.java',
    '.swift',
    '.m',
    '.mm',
    '.c',
    '.cc',
    '.cpp',
    '.cxx',
    '.h',
    '.hpp',
    '.cs',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.py',
    '.rb',
    '.go',
    '.rs',
    '.php',
    '.html',
    '.css',
    '.scss',
    '.json',
    '.yaml',
    '.yml',
    '.xml',
    '.sh',
    '.bat',
    '.ps1',
    '.exe',
    '.msi',
    '.apk',
    '.ipa',
    '.deb',
    '.rpm',
    '.appimage',
    '.zip',
    '.tar',
    '.gz',
    '.7z',
  };
}

class _RemoteOwnerDraft {
  _RemoteOwnerDraft({
    required this.ip,
    required this.name,
    required this.macAddress,
  });

  final String ip;
  final String name;
  final String macAddress;
  int shareCount = 0;
  int fileCount = 0;
  int cachedShareCount = 0;
}
