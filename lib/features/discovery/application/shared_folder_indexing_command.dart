import 'dart:math' as math;

import '../../settings/domain/app_settings.dart';
import '../../transfer/application/shared_cache_owner_contracts.dart';

typedef SharedFolderCacheUpsert =
    Future<OwnerFolderCacheUpsertResult> Function({
      required String ownerMacAddress,
      required String folderPath,
      String? displayName,
      int? parallelWorkers,
      OwnerCacheProgressCallback? onProgress,
    });

class SharedFolderIndexingProgress {
  const SharedFolderIndexingProgress({
    required this.processedFiles,
    required this.totalFiles,
    required this.currentRelativePath,
    required this.stage,
    required this.eta,
  });

  final int processedFiles;
  final int totalFiles;
  final String currentRelativePath;
  final OwnerCacheProgressStage stage;
  final Duration? eta;
}

class SharedFolderIndexingState {
  const SharedFolderIndexingState({
    required this.isAddingShare,
    this.progress,
    this.visualProgress,
  });

  final bool isAddingShare;
  final SharedFolderIndexingProgress? progress;
  final double? visualProgress;
}

class SharedFolderIndexingCommandResult {
  const SharedFolderIndexingCommandResult._({
    required this.infoMessage,
    required this.cancelled,
  });

  const SharedFolderIndexingCommandResult.completed(String infoMessage)
    : this._(infoMessage: infoMessage, cancelled: false);

  const SharedFolderIndexingCommandResult.cancelled()
    : this._(infoMessage: null, cancelled: true);

  final String? infoMessage;
  final bool cancelled;
}

class SharedFolderIndexingCommand {
  SharedFolderIndexingCommand({
    required SharedFolderCacheUpsert upsertOwnerFolderCache,
    required String Function() localDeviceMacProvider,
    required AppSettings Function() settingsProvider,
    required Future<bool> Function() ensureSharedStorageAccess,
    required Future<String?> Function() pickFolderPath,
    required Future<void> Function() loadOwnerCaches,
    required void Function(SharedFolderIndexingState state) onStateChanged,
    required DateTime Function() nowProvider,
    Duration uiTickInterval = const Duration(milliseconds: 120),
  }) : _upsertOwnerFolderCache = upsertOwnerFolderCache,
       _localDeviceMacProvider = localDeviceMacProvider,
       _settingsProvider = settingsProvider,
       _ensureSharedStorageAccess = ensureSharedStorageAccess,
       _pickFolderPath = pickFolderPath,
       _loadOwnerCaches = loadOwnerCaches,
       _onStateChanged = onStateChanged,
       _now = nowProvider,
       _uiTickInterval = uiTickInterval;

  static const double _scanProgressWeight = 0.35;

  final SharedFolderCacheUpsert _upsertOwnerFolderCache;
  final String Function() _localDeviceMacProvider;
  final AppSettings Function() _settingsProvider;
  final Future<bool> Function() _ensureSharedStorageAccess;
  final Future<String?> Function() _pickFolderPath;
  final Future<void> Function() _loadOwnerCaches;
  final void Function(SharedFolderIndexingState state) _onStateChanged;
  final DateTime Function() _now;
  final Duration _uiTickInterval;

  Future<SharedFolderIndexingCommandResult> run() async {
    _onStateChanged(const SharedFolderIndexingState(isAddingShare: true));

    try {
      if (!await _ensureSharedStorageAccess()) {
        return const SharedFolderIndexingCommandResult.cancelled();
      }

      final folderPath = await _pickFolderPath();
      if (folderPath == null || folderPath.trim().isEmpty) {
        return const SharedFolderIndexingCommandResult.cancelled();
      }

      _emitInitialProgress();
      final result = await _indexFolder(folderPath.trim());
      await _loadOwnerCaches();

      return SharedFolderIndexingCommandResult.completed(
        _buildCompletionMessage(result),
      );
    } finally {
      _onStateChanged(const SharedFolderIndexingState(isAddingShare: false));
    }
  }

  Future<OwnerFolderCacheUpsertResult> _indexFolder(String folderPath) async {
    final indexingStopwatch = Stopwatch()..start();
    DateTime? lastUiTickAt;
    var visualProgress = 0.0;

    final result = await _upsertOwnerFolderCache(
      ownerMacAddress: _localDeviceMacProvider(),
      folderPath: folderPath,
      parallelWorkers: _resolveRecacheParallelWorkersOverride(),
      onProgress:
          ({
            required int processedFiles,
            required int totalFiles,
            required String relativePath,
            required OwnerCacheProgressStage stage,
          }) {
            final safeProcessedFiles = math.max(0, processedFiles);
            final safeTotalFiles = math.max(0, totalFiles);
            final progress = _mapProgress(
              elapsed: indexingStopwatch.elapsed,
              processedFiles: safeProcessedFiles,
              totalFiles: safeTotalFiles,
              relativePath: relativePath,
              stage: stage,
              currentVisualProgress: visualProgress,
            );
            visualProgress = progress.visualProgress ?? visualProgress;
            final now = _now();
            final shouldNotify =
                lastUiTickAt == null ||
                now.difference(lastUiTickAt!) >= _uiTickInterval ||
                (safeTotalFiles > 0 && safeProcessedFiles >= safeTotalFiles);
            if (shouldNotify) {
              lastUiTickAt = now;
              _onStateChanged(progress);
            }
          },
    );

    indexingStopwatch.stop();
    final completedCount = math.max(0, result.record.itemCount);
    _onStateChanged(
      SharedFolderIndexingState(
        isAddingShare: true,
        progress: SharedFolderIndexingProgress(
          processedFiles: completedCount,
          totalFiles: completedCount,
          currentRelativePath: '',
          stage: OwnerCacheProgressStage.indexing,
          eta: Duration.zero,
        ),
        visualProgress: 1,
      ),
    );
    return result;
  }

  void _emitInitialProgress() {
    _onStateChanged(
      const SharedFolderIndexingState(
        isAddingShare: true,
        progress: SharedFolderIndexingProgress(
          processedFiles: 0,
          totalFiles: 0,
          currentRelativePath: '',
          stage: OwnerCacheProgressStage.scanning,
          eta: null,
        ),
        visualProgress: 0,
      ),
    );
  }

  SharedFolderIndexingState _mapProgress({
    required Duration elapsed,
    required int processedFiles,
    required int totalFiles,
    required String relativePath,
    required OwnerCacheProgressStage stage,
    required double currentVisualProgress,
  }) {
    Duration? eta;
    double nextVisualProgress;
    if (stage == OwnerCacheProgressStage.scanning || totalFiles <= 0) {
      nextVisualProgress = _estimateScanProgress(processedFiles);
    } else {
      final fileProgress = (processedFiles / totalFiles).clamp(0, 1).toDouble();
      nextVisualProgress =
          _scanProgressWeight + fileProgress * (1 - _scanProgressWeight);
      eta = _estimateEta(
        elapsed: elapsed,
        processedFiles: processedFiles,
        totalFiles: totalFiles,
      );
    }

    return SharedFolderIndexingState(
      isAddingShare: true,
      progress: SharedFolderIndexingProgress(
        processedFiles: processedFiles,
        totalFiles: totalFiles,
        currentRelativePath: relativePath,
        stage: stage,
        eta: eta,
      ),
      visualProgress: math
          .max(currentVisualProgress, nextVisualProgress)
          .clamp(0, 1)
          .toDouble(),
    );
  }

  double _estimateScanProgress(int discoveredFiles) {
    if (discoveredFiles <= 0) {
      return 0;
    }
    final normalized = 1 - math.exp(-(discoveredFiles / 3000));
    final weighted = normalized * _scanProgressWeight;
    return weighted.clamp(0, _scanProgressWeight).toDouble();
  }

  Duration? _estimateEta({
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
    final configured = _settingsProvider().recacheParallelWorkers;
    if (configured <= 0) {
      return null;
    }
    return configured;
  }

  String _buildCompletionMessage(OwnerFolderCacheUpsertResult result) {
    final delta = result.record.itemCount - result.previousItemCount;
    if (result.created) {
      return 'Shared folder added. Indexed ${result.record.itemCount} file(s).';
    }
    if (delta > 0) {
      return 'Shared folder updated. Found $delta new file(s), '
          'total ${result.record.itemCount}.';
    }
    return 'Shared folder re-cached. No new files, '
        'total ${result.record.itemCount}.';
  }
}
