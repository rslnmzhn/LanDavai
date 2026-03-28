import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_notification_service.dart';
import '../../settings/domain/app_settings.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/data/shared_folder_cache_repository.dart';
import '../../transfer/domain/shared_folder_cache.dart';

class SharedCacheSummary {
  const SharedCacheSummary({
    required this.totalCaches,
    required this.folderCaches,
    required this.selectionCaches,
    required this.totalFiles,
  });

  final int totalCaches;
  final int folderCaches;
  final int selectionCaches;
  final int totalFiles;
}

class SharedCacheMaintenanceProgress {
  const SharedCacheMaintenanceProgress({
    required this.processedCaches,
    required this.totalCaches,
    required this.processedFiles,
    required this.totalFiles,
    required this.currentCacheLabel,
    required this.currentRelativePath,
    required this.eta,
  });

  final int processedCaches;
  final int totalCaches;
  final int processedFiles;
  final int totalFiles;
  final String currentCacheLabel;
  final String currentRelativePath;
  final Duration? eta;
}

class SharedCacheRecacheReport {
  const SharedCacheRecacheReport({
    required this.before,
    required this.after,
    required this.updatedCaches,
    required this.failedCaches,
  });

  final SharedCacheSummary before;
  final SharedCacheSummary after;
  final int updatedCaches;
  final int failedCaches;
}

class SharedCacheMaintenanceBoundary extends ChangeNotifier {
  SharedCacheMaintenanceBoundary({
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required AppNotificationService appNotificationService,
    required String Function() ownerMacAddressProvider,
    AppSettings Function()? settingsProvider,
  }) : _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _appNotificationService = appNotificationService,
       _ownerMacAddressProvider = ownerMacAddressProvider,
       _settingsProvider = settingsProvider;

  static const Duration _sharedRecacheCooldown = Duration(minutes: 5);
  static const Duration _sharedRecacheUiTickInterval = Duration(
    milliseconds: 120,
  );
  static const Duration _sharedRecacheNotificationTickInterval = Duration(
    milliseconds: 900,
  );

  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final AppNotificationService _appNotificationService;
  final String Function() _ownerMacAddressProvider;
  final AppSettings Function()? _settingsProvider;

  bool _isRecacheInProgress = false;
  SharedCacheMaintenanceProgress? _recacheProgress;
  double? _recacheProgressValue;
  DateTime? _recacheCooldownUntil;

  bool get isRecacheInProgress => _isRecacheInProgress;
  SharedCacheMaintenanceProgress? get recacheProgress => _recacheProgress;
  double? get recacheProgressValue => _recacheProgressValue;

  bool get isRecacheCooldownActive {
    final until = _recacheCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Duration? get recacheCooldownRemaining {
    final until = _recacheCooldownUntil;
    if (until == null) {
      return null;
    }
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      return null;
    }
    return remaining;
  }

  Future<SharedCacheSummary> summarizeOwnerSharedContent({
    String virtualFolderPath = '',
  }) async {
    final caches = await _loadOwnerCaches();
    final normalizedFolder = _normalizeVirtualFolderPath(virtualFolderPath);
    if (normalizedFolder.isEmpty) {
      return _buildSharedCacheSummary(caches);
    }
    final targets = await _resolveScopedOwnerRecacheTargets(
      caches: caches,
      virtualFolderPath: normalizedFolder,
    );
    return _buildScopedSharedCacheSummary(targets);
  }

  Future<bool> removeCacheById(String cacheId) async {
    final trimmedCacheId = cacheId.trim();
    if (trimmedCacheId.isEmpty) {
      return false;
    }
    final caches = await _loadOwnerCaches();
    SharedFolderCacheRecord? target;
    for (final cache in caches) {
      if (cache.cacheId == trimmedCacheId) {
        target = cache;
        break;
      }
    }
    if (target == null) {
      return false;
    }

    await _sharedCacheCatalog.deleteCache(trimmedCacheId);
    await _loadOwnerCaches();
    return true;
  }

  Future<SharedCacheRecacheReport?> recacheOwner({
    String virtualFolderPath = '',
  }) async {
    if (_isRecacheInProgress || isRecacheCooldownActive) {
      return null;
    }

    _isRecacheInProgress = true;
    _recacheProgress = null;
    _recacheProgressValue = null;
    notifyListeners();

    var shouldStartCooldown = false;
    final recacheStopwatch = Stopwatch()..start();
    DateTime? lastUiTickAt;
    DateTime? lastNotificationTickAt;
    try {
      final normalizedScopeFolder = _normalizeVirtualFolderPath(
        virtualFolderPath,
      );
      final targets = await _resolveScopedOwnerRecacheTargets(
        caches: await _loadOwnerCaches(),
        virtualFolderPath: normalizedScopeFolder,
      );
      if (targets.isEmpty) {
        return null;
      }

      final before = _buildScopedSharedCacheSummary(targets);
      var updatedCount = 0;
      var failedCount = 0;
      final totalCaches = targets.length;
      var estimatedTotalFiles = targets.fold<int>(
        0,
        (sum, target) => sum + math.max(target.estimatedFileCount, 0),
      );
      var processedFilesAcrossCaches = 0;

      void publishProgress({
        required int processedCaches,
        required int processedFiles,
        required int totalFiles,
        required String currentCacheLabel,
        required String currentRelativePath,
        bool force = false,
      }) {
        final safeProcessedFiles = math.max(0, processedFiles);
        final safeTotalFiles = math.max(totalFiles, safeProcessedFiles);
        final progress = SharedCacheMaintenanceProgress(
          processedCaches: processedCaches.clamp(0, totalCaches),
          totalCaches: totalCaches,
          processedFiles: safeProcessedFiles,
          totalFiles: safeTotalFiles,
          currentCacheLabel: currentCacheLabel,
          currentRelativePath: currentRelativePath,
          eta: _estimateRecacheEta(
            elapsed: recacheStopwatch.elapsed,
            processedFiles: safeProcessedFiles,
            totalFiles: safeTotalFiles,
          ),
        );
        _recacheProgress = progress;
        _recacheProgressValue = _resolveSharedRecacheProgressValue(progress);

        final now = DateTime.now();
        final shouldNotifyUi =
            force ||
            lastUiTickAt == null ||
            now.difference(lastUiTickAt!) >= _sharedRecacheUiTickInterval;
        if (shouldNotifyUi) {
          lastUiTickAt = now;
          notifyListeners();
        }

        final shouldNotifyPlatform =
            force ||
            lastNotificationTickAt == null ||
            now.difference(lastNotificationTickAt!) >=
                _sharedRecacheNotificationTickInterval;
        if (shouldNotifyPlatform) {
          lastNotificationTickAt = now;
          unawaited(
            _appNotificationService.showSharedRecacheProgressNotification(
              processedCaches: progress.processedCaches,
              totalCaches: progress.totalCaches,
              currentCacheLabel: progress.currentCacheLabel,
              processedFiles: progress.processedFiles,
              totalFiles: progress.totalFiles > 0 ? progress.totalFiles : null,
              etaSeconds: progress.eta?.inSeconds,
              currentFileLabel: progress.currentRelativePath.isEmpty
                  ? null
                  : progress.currentRelativePath,
            ),
          );
        }
      }

      publishProgress(
        processedCaches: 0,
        processedFiles: 0,
        totalFiles: estimatedTotalFiles,
        currentCacheLabel: '',
        currentRelativePath: '',
        force: true,
      );

      for (var index = 0; index < targets.length; index++) {
        final target = targets[index];
        final cache = target.cache;
        var cacheTotalFiles = math.max(target.estimatedFileCount, 0);
        var cacheProcessedFiles = 0;

        void handleCacheFileProgress({
          required int processedFiles,
          required int totalFiles,
          required String relativePath,
          required OwnerCacheProgressStage stage,
        }) {
          if (stage == OwnerCacheProgressStage.scanning) {
            return;
          }
          cacheProcessedFiles = math.max(0, processedFiles);
          final normalizedTotal = math.max(totalFiles, cacheProcessedFiles);
          if (normalizedTotal != cacheTotalFiles) {
            estimatedTotalFiles += normalizedTotal - cacheTotalFiles;
            cacheTotalFiles = normalizedTotal;
          }
          final globalProcessed =
              processedFilesAcrossCaches + cacheProcessedFiles;
          if (estimatedTotalFiles < globalProcessed) {
            estimatedTotalFiles = globalProcessed;
          }
          publishProgress(
            processedCaches: index,
            processedFiles: globalProcessed,
            totalFiles: estimatedTotalFiles,
            currentCacheLabel: target.label,
            currentRelativePath: relativePath,
          );
        }

        try {
          if (cache.rootPath.startsWith('selection://')) {
            await _sharedCacheCatalog.refreshOwnerSelectionCacheEntries(
              cache,
              onProgress: handleCacheFileProgress,
            );
          } else if (target.relativeFolderPath.isEmpty) {
            await _sharedCacheCatalog.upsertOwnerFolderCache(
              ownerMacAddress: _ownerMacAddressProvider(),
              folderPath: cache.rootPath,
              displayName: cache.displayName,
              parallelWorkers: _resolveRecacheParallelWorkersOverride(),
              onProgress: handleCacheFileProgress,
            );
          } else {
            await _sharedCacheCatalog.refreshOwnerFolderSubdirectoryEntries(
              cache,
              relativeFolderPath: target.relativeFolderPath,
              parallelWorkers: _resolveRecacheParallelWorkersOverride(),
              onProgress: handleCacheFileProgress,
            );
          }
          updatedCount += 1;
        } catch (_) {
          failedCount += 1;
        }

        final finalizedCacheFiles = math.max(
          cacheProcessedFiles,
          cacheTotalFiles,
        );
        processedFilesAcrossCaches += finalizedCacheFiles;
        if (estimatedTotalFiles < processedFilesAcrossCaches) {
          estimatedTotalFiles = processedFilesAcrossCaches;
        }
        publishProgress(
          processedCaches: index + 1,
          processedFiles: processedFilesAcrossCaches,
          totalFiles: estimatedTotalFiles,
          currentCacheLabel: target.label,
          currentRelativePath: '',
          force: true,
        );
      }

      final afterTargets = await _resolveScopedOwnerRecacheTargets(
        caches: await _loadOwnerCaches(),
        virtualFolderPath: normalizedScopeFolder,
      );
      final report = SharedCacheRecacheReport(
        before: before,
        after: _buildScopedSharedCacheSummary(afterTargets),
        updatedCaches: updatedCount,
        failedCaches: failedCount,
      );
      shouldStartCooldown = true;
      _recacheCooldownUntil = DateTime.now().add(_sharedRecacheCooldown);

      await _appNotificationService.showSharedRecacheCompletedNotification(
        beforeFiles: report.before.totalFiles,
        afterFiles: report.after.totalFiles,
      );
      return report;
    } finally {
      recacheStopwatch.stop();
      _isRecacheInProgress = false;
      _recacheProgress = null;
      _recacheProgressValue = null;
      if (!shouldStartCooldown) {
        _recacheCooldownUntil = null;
      }
      notifyListeners();
    }
  }

  Future<List<SharedFolderCacheRecord>> _loadOwnerCaches() async {
    final ownerMacAddress = _ownerMacAddressProvider().trim();
    if (ownerMacAddress.isNotEmpty) {
      try {
        await _sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: ownerMacAddress,
        );
      } catch (_) {
        // Keep using the last loaded owner snapshot in the current session.
      }
    }
    return _sharedCacheCatalog.ownerCaches;
  }

  Future<List<_ScopedOwnerRecacheTarget>> _resolveScopedOwnerRecacheTargets({
    required List<SharedFolderCacheRecord> caches,
    required String virtualFolderPath,
  }) async {
    final normalizedFolder = _normalizeVirtualFolderPath(virtualFolderPath);
    final targets = <_ScopedOwnerRecacheTarget>[];
    for (final cache in caches) {
      final isSelection = cache.rootPath.startsWith('selection://');
      if (isSelection) {
        if (normalizedFolder.isNotEmpty) {
          continue;
        }
        targets.add(
          _ScopedOwnerRecacheTarget(
            cache: cache,
            relativeFolderPath: '',
            estimatedFileCount: math.max(cache.itemCount, 0),
          ),
        );
        continue;
      }

      final cacheVirtualRoot = _normalizeVirtualFolderPath(cache.displayName);
      if (normalizedFolder.isNotEmpty &&
          normalizedFolder != cacheVirtualRoot &&
          !normalizedFolder.startsWith('$cacheVirtualRoot/')) {
        continue;
      }

      final relativeFolderPath =
          normalizedFolder.isEmpty || normalizedFolder == cacheVirtualRoot
          ? ''
          : normalizedFolder.substring(cacheVirtualRoot.length + 1);

      var estimatedFiles = math.max(cache.itemCount, 0);
      if (relativeFolderPath.isNotEmpty) {
        estimatedFiles = await _countFilesInCacheFolder(
          cache: cache,
          relativeFolderPath: relativeFolderPath,
        );
      }

      targets.add(
        _ScopedOwnerRecacheTarget(
          cache: cache,
          relativeFolderPath: relativeFolderPath,
          estimatedFileCount: estimatedFiles,
        ),
      );
    }
    return targets;
  }

  Future<int> _countFilesInCacheFolder({
    required SharedFolderCacheRecord cache,
    required String relativeFolderPath,
  }) async {
    final normalizedFolder = _normalizeVirtualFolderPath(relativeFolderPath);
    final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
    if (normalizedFolder.isEmpty) {
      return entries.length;
    }
    var count = 0;
    for (final entry in entries) {
      if (_isCacheEntryWithinFolder(entry.relativePath, normalizedFolder)) {
        count += 1;
      }
    }
    return count;
  }

  SharedCacheSummary _buildSharedCacheSummary(
    List<SharedFolderCacheRecord> caches,
  ) {
    var folderCaches = 0;
    var selectionCaches = 0;
    var totalFiles = 0;
    for (final cache in caches) {
      totalFiles += cache.itemCount;
      if (cache.rootPath.startsWith('selection://')) {
        selectionCaches += 1;
      } else {
        folderCaches += 1;
      }
    }
    return SharedCacheSummary(
      totalCaches: caches.length,
      folderCaches: folderCaches,
      selectionCaches: selectionCaches,
      totalFiles: totalFiles,
    );
  }

  SharedCacheSummary _buildScopedSharedCacheSummary(
    List<_ScopedOwnerRecacheTarget> targets,
  ) {
    var folderCaches = 0;
    var selectionCaches = 0;
    var totalFiles = 0;
    for (final target in targets) {
      totalFiles += math.max(target.estimatedFileCount, 0);
      if (target.cache.rootPath.startsWith('selection://')) {
        selectionCaches += 1;
      } else {
        folderCaches += 1;
      }
    }
    return SharedCacheSummary(
      totalCaches: targets.length,
      folderCaches: folderCaches,
      selectionCaches: selectionCaches,
      totalFiles: totalFiles,
    );
  }

  bool _isCacheEntryWithinFolder(String relativePath, String folderPath) {
    final normalizedRelative = _normalizeVirtualFolderPath(relativePath);
    final normalizedFolder = _normalizeVirtualFolderPath(folderPath);
    if (normalizedFolder.isEmpty) {
      return true;
    }
    return normalizedRelative == normalizedFolder ||
        normalizedRelative.startsWith('$normalizedFolder/');
  }

  double _resolveSharedRecacheProgressValue(
    SharedCacheMaintenanceProgress progress,
  ) {
    if (progress.totalFiles > 0) {
      final value = progress.processedFiles / progress.totalFiles;
      return value.clamp(0, 1).toDouble();
    }
    if (progress.totalCaches <= 0) {
      return 0;
    }
    final value = progress.processedCaches / progress.totalCaches;
    return value.clamp(0, 1).toDouble();
  }

  Duration? _estimateRecacheEta({
    required Duration elapsed,
    required int processedFiles,
    required int totalFiles,
  }) {
    if (processedFiles <= 0 || totalFiles <= processedFiles) {
      return null;
    }
    final elapsedMs = elapsed.inMilliseconds;
    if (elapsedMs <= 0) {
      return null;
    }
    final remainingFiles = totalFiles - processedFiles;
    final etaMs = ((elapsedMs * remainingFiles) / processedFiles).round();
    if (etaMs <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: etaMs);
  }

  int? _resolveRecacheParallelWorkersOverride() {
    final configured = _settingsProvider?.call().recacheParallelWorkers ?? 0;
    if (configured <= 0) {
      return null;
    }
    return configured;
  }

  String _normalizeVirtualFolderPath(String value) {
    return value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }
}

class _ScopedOwnerRecacheTarget {
  const _ScopedOwnerRecacheTarget({
    required this.cache,
    required this.relativeFolderPath,
    required this.estimatedFileCount,
  });

  final SharedFolderCacheRecord cache;
  final String relativeFolderPath;
  final int estimatedFileCount;

  String get label {
    if (relativeFolderPath.isEmpty) {
      return cache.displayName;
    }
    return '${cache.displayName}/$relativeFolderPath';
  }
}
