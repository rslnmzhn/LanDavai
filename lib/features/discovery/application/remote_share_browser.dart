import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
  const RemoteBrowseProjection({
    required this.options,
    required this.owners,
    required this.selectedOwnerIp,
    required this.selectedOwner,
    required this.files,
    required this.folders,
    required this.selectedFileIds,
    required this.selectedFolderIds,
    required this.effectiveSelectedFileIds,
    required this.folderCoveredFileIds,
    required this.isFileListCapped,
    required this.hiddenFilesCount,
  });

  final List<RemoteShareOption> options;
  final List<RemoteBrowseOwnerChoice> owners;
  final String? selectedOwnerIp;
  final RemoteBrowseOwnerChoice? selectedOwner;
  final List<RemoteBrowseFileChoice> files;
  final List<RemoteBrowseFolderChoice> folders;
  final Set<String> selectedFileIds;
  final Set<String> selectedFolderIds;
  final Set<String> effectiveSelectedFileIds;
  final Set<String> folderCoveredFileIds;
  final bool isFileListCapped;
  final int hiddenFilesCount;

  int get selectedCount => effectiveSelectedFileIds.length;
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

enum RemoteBrowseMediaKind { image, video, other }

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

class RemoteShareBrowser extends ChangeNotifier {
  RemoteShareBrowser({
    required SharedCacheCatalog sharedCacheCatalog,
    this.maxFilesPerCacheForUi = 4000,
    this.maxVisibleFiles = 2500,
  }) : _sharedCacheCatalog = sharedCacheCatalog;

  final SharedCacheCatalog _sharedCacheCatalog;
  final int maxFilesPerCacheForUi;
  final int maxVisibleFiles;

  final List<RemoteShareOption> _options = <RemoteShareOption>[];
  final Map<String, String> _previewPathsByFileKey = <String, String>{};
  final Map<String, SharedFolderCacheRecord> _receiverSnapshotsByRemoteCacheId =
      <String, SharedFolderCacheRecord>{};
  final Set<String> _selectedFileIds = <String>{};
  final Set<String> _selectedFolderIds = <String>{};

  bool _isLoading = false;
  String? _selectedOwnerIp;
  String? _activeRequestId;
  String? _receiverMacAddress;

  bool get isLoading => _isLoading;

  RemoteBrowseProjection get currentBrowseProjection {
    final owners = _buildOwnerChoices();
    final selectedOwner = _selectedOwnerIp == null
        ? null
        : _findOwnerByIp(owners, _selectedOwnerIp!);
    final files = selectedOwner == null
        ? const <RemoteBrowseFileChoice>[]
        : _buildFileChoices(ownerIp: selectedOwner.ip);
    final folders = selectedOwner == null
        ? const <RemoteBrowseFolderChoice>[]
        : _buildFolderChoices(files);
    final selectedFolderPathsByCache = _buildSelectedFolderPathsByCache(
      folders: folders,
    );
    final effectiveSelectedFileIds = <String>{};
    final folderCoveredFileIds = <String>{};
    for (final file in files) {
      if (_selectedFileIds.contains(file.id)) {
        effectiveSelectedFileIds.add(file.id);
        continue;
      }
      final cacheKey = _cacheSelectionKey(
        ownerIp: file.ownerIp,
        cacheId: file.cacheId,
      );
      if (_matchesFolderSelection(
        relativePath: file.relativePath,
        selectedFolderPaths: selectedFolderPathsByCache[cacheKey],
      )) {
        effectiveSelectedFileIds.add(file.id);
        folderCoveredFileIds.add(file.id);
      }
    }
    final hiddenFilesCount =
        selectedOwner == null || files.length >= selectedOwner.fileCount
        ? 0
        : selectedOwner.fileCount - files.length;
    return RemoteBrowseProjection(
      options: List<RemoteShareOption>.unmodifiable(_options),
      owners: owners,
      selectedOwnerIp: _selectedOwnerIp,
      selectedOwner: selectedOwner,
      files: files,
      folders: folders,
      selectedFileIds: Set<String>.unmodifiable(_selectedFileIds),
      selectedFolderIds: Set<String>.unmodifiable(_selectedFolderIds),
      effectiveSelectedFileIds: Set<String>.unmodifiable(
        effectiveSelectedFileIds,
      ),
      folderCoveredFileIds: Set<String>.unmodifiable(folderCoveredFileIds),
      isFileListCapped: hiddenFilesCount > 0,
      hiddenFilesCount: hiddenFilesCount,
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
    _selectedOwnerIp = null;
    _selectedFileIds.clear();
    _selectedFolderIds.clear();
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
    _reconcileSelection();
    notifyListeners();
  }

  void selectOwner(String? ownerIp) {
    if (_selectedOwnerIp == ownerIp) {
      return;
    }
    _selectedOwnerIp = ownerIp;
    _selectedFileIds.clear();
    _selectedFolderIds.clear();
    _reconcileSelection();
    notifyListeners();
  }

  void selectVisibleFiles(Iterable<String> fileIds) {
    _selectedFolderIds.clear();
    _selectedFileIds
      ..clear()
      ..addAll(fileIds);
    _reconcileSelection();
    notifyListeners();
  }

  void setSelectedFolderIds(Set<String> folderIds) {
    _selectedFolderIds
      ..clear()
      ..addAll(folderIds);
    _reconcileSelection();
    notifyListeners();
  }

  void setFileSelected({required String fileId, required bool isSelected}) {
    if (isSelected) {
      _selectedFileIds.add(fileId);
    } else {
      _selectedFileIds.remove(fileId);
    }
    _reconcileSelection();
    notifyListeners();
  }

  void clearSelections() {
    if (_selectedFileIds.isEmpty && _selectedFolderIds.isEmpty) {
      return;
    }
    _selectedFileIds.clear();
    _selectedFolderIds.clear();
    notifyListeners();
  }

  Map<String, Set<String>> buildSelectedRelativePathsByCache() {
    final projection = currentBrowseProjection;
    final selectedByCache = <String, Set<String>>{};
    for (final file in projection.files) {
      final picked =
          projection.selectedFileIds.contains(file.id) ||
          projection.folderCoveredFileIds.contains(file.id);
      if (!picked) {
        continue;
      }
      selectedByCache
          .putIfAbsent(file.cacheId, () => <String>{})
          .add(file.relativePath);
    }
    return selectedByCache;
  }

  Map<String, Set<String>> buildDownloadAllRequestForOwner(String ownerIp) {
    final selectedByCache = <String, Set<String>>{};
    for (final option in _options) {
      if (option.ownerIp != ownerIp) {
        continue;
      }
      selectedByCache[option.entry.cacheId] = <String>{};
    }
    return selectedByCache;
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

  void _reconcileSelection() {
    final owners = _buildOwnerChoices();
    final selectedOwner = _selectedOwnerIp == null
        ? null
        : _findOwnerByIp(owners, _selectedOwnerIp!);
    if (selectedOwner == null) {
      _selectedOwnerIp = null;
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
      return;
    }

    final files = _buildFileChoices(ownerIp: selectedOwner.ip);
    final validFileIds = files.map((file) => file.id).toSet();
    _selectedFileIds.removeWhere((id) => !validFileIds.contains(id));

    final folders = _buildFolderChoices(files);
    final validFolderIds = folders.map((folder) => folder.id).toSet();
    _selectedFolderIds.removeWhere((id) => !validFolderIds.contains(id));
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

  RemoteBrowseOwnerChoice? _findOwnerByIp(
    List<RemoteBrowseOwnerChoice> owners,
    String ip,
  ) {
    for (final owner in owners) {
      if (owner.ip == ip) {
        return owner;
      }
    }
    return null;
  }

  List<RemoteBrowseFileChoice> _buildFileChoices({required String ownerIp}) {
    final files = <RemoteBrowseFileChoice>[];
    for (final option in _options) {
      if (option.ownerIp != ownerIp) {
        continue;
      }
      for (final file in option.entry.files) {
        if (files.length >= maxVisibleFiles) {
          break;
        }
        files.add(
          RemoteBrowseFileChoice(
            ownerIp: option.ownerIp,
            ownerName: option.ownerName,
            cacheId: option.entry.cacheId,
            cacheDisplayName: option.entry.displayName,
            relativePath: file.relativePath,
            sizeBytes: file.sizeBytes,
            thumbnailId: file.thumbnailId,
            previewPath: previewPathFor(
              ownerIp: option.ownerIp,
              cacheId: option.entry.cacheId,
              relativePath: file.relativePath,
            ),
            hasReceiverCacheSnapshot: option.hasReceiverCacheSnapshot,
          ),
        );
      }
      if (files.length >= maxVisibleFiles) {
        break;
      }
    }
    files.sort((a, b) {
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      return a.relativePath.toLowerCase().compareTo(
        b.relativePath.toLowerCase(),
      );
    });
    return files;
  }

  List<RemoteBrowseFolderChoice> _buildFolderChoices(
    List<RemoteBrowseFileChoice> files,
  ) {
    final byId = <String, _RemoteFolderDraft>{};
    for (final file in files) {
      final folderPaths = <String>[
        '',
        ..._extractFolderPaths(file.relativePath),
      ];
      for (final folderPath in folderPaths) {
        final id = _folderId(
          ownerIp: file.ownerIp,
          cacheId: file.cacheId,
          folderPath: folderPath,
        );
        final draft = byId.putIfAbsent(
          id,
          () => _RemoteFolderDraft(
            ownerIp: file.ownerIp,
            cacheId: file.cacheId,
            cacheDisplayName: file.cacheDisplayName,
            folderPath: folderPath,
          ),
        );
        if (draft.fileIds.add(file.id)) {
          draft.fileCount += 1;
          draft.totalBytes += file.sizeBytes;
        }
      }
    }

    final folders = byId.values
        .map(
          (draft) => RemoteBrowseFolderChoice(
            ownerIp: draft.ownerIp,
            cacheId: draft.cacheId,
            cacheDisplayName: draft.cacheDisplayName,
            folderPath: draft.folderPath,
            fileCount: draft.fileCount,
            totalBytes: draft.totalBytes,
          ),
        )
        .toList(growable: false);
    folders.sort((a, b) {
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      final depthCmp = a.depth.compareTo(b.depth);
      if (depthCmp != 0) {
        return depthCmp;
      }
      return a.folderPath.toLowerCase().compareTo(b.folderPath.toLowerCase());
    });
    return folders;
  }

  Map<String, Set<String>> _buildSelectedFolderPathsByCache({
    required List<RemoteBrowseFolderChoice> folders,
  }) {
    final byCache = <String, Set<String>>{};
    for (final folder in folders) {
      if (!_selectedFolderIds.contains(folder.id)) {
        continue;
      }
      final cacheKey = _cacheSelectionKey(
        ownerIp: folder.ownerIp,
        cacheId: folder.cacheId,
      );
      byCache.putIfAbsent(cacheKey, () => <String>{}).add(folder.folderPath);
    }
    return byCache;
  }

  bool _matchesFolderSelection({
    required String relativePath,
    required Set<String>? selectedFolderPaths,
  }) {
    if (selectedFolderPaths == null || selectedFolderPaths.isEmpty) {
      return false;
    }
    final normalizedPath = _normalizeRelativePath(relativePath);
    for (final folderPath in selectedFolderPaths) {
      final normalizedFolder = _normalizeRelativePath(folderPath);
      if (normalizedFolder.isEmpty) {
        return true;
      }
      if (normalizedPath == normalizedFolder ||
          normalizedPath.startsWith('$normalizedFolder/')) {
        return true;
      }
    }
    return false;
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

  String _cacheSelectionKey({
    required String ownerIp,
    required String cacheId,
  }) {
    return '$ownerIp|$cacheId';
  }

  String _folderId({
    required String ownerIp,
    required String cacheId,
    required String folderPath,
  }) {
    return '$ownerIp|$cacheId|$folderPath';
  }

  String _previewKey({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
  }) {
    final normalizedPath = relativePath.replaceAll('\\', '/').toLowerCase();
    return '$ownerIp|$cacheId|$normalizedPath';
  }

  List<String> _extractFolderPaths(String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) {
      return const <String>[];
    }

    final folders = <String>[];
    for (var i = 1; i < parts.length; i++) {
      folders.add(parts.take(i).join('/'));
    }
    return folders;
  }

  String _normalizeRelativePath(String value) {
    return value.replaceAll('\\', '/').trim();
  }
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

class _RemoteFolderDraft {
  _RemoteFolderDraft({
    required this.ownerIp,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.folderPath,
  });

  final String ownerIp;
  final String cacheId;
  final String cacheDisplayName;
  final String folderPath;
  int fileCount = 0;
  int totalBytes = 0;
  final Set<String> fileIds = <String>{};
}
