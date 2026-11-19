import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/app_update_models.dart';

class AppUpdateBoundary extends ChangeNotifier {
  static const String fileNotFoundMessage = 'File not found - download again.';

  AppUpdateBoundary({
    required Future<String> Function() currentVersionLoader,
    required Future<AppUpdateRelease> Function() latestReleaseLoader,
    required Future<AppUpdateTarget> Function() targetResolver,
    required AppUpdateAsset Function({
      required AppUpdateRelease release,
      required AppUpdateTarget target,
    })
    assetSelector,
    Future<File> Function(AppUpdateAsset asset)? assetDownloader,
    Future<File> Function(
      AppUpdateAsset asset, {
      AppUpdateDownloadProgressCallback? onProgress,
    })?
    assetDownloaderWithProgress,
    required Future<void> Function({
      required AppUpdateAsset asset,
      required File file,
    })
    downloadedAssetInstaller,
  }) : assert(
         assetDownloader != null || assetDownloaderWithProgress != null,
         'Either assetDownloader or assetDownloaderWithProgress must be provided.',
       ),
       _currentVersionLoader = currentVersionLoader,
       _latestReleaseLoader = latestReleaseLoader,
       _targetResolver = targetResolver,
       _assetSelector = assetSelector,
       _assetDownloader = assetDownloader,
       _assetDownloaderWithProgress = assetDownloaderWithProgress,
       _downloadedAssetInstaller = downloadedAssetInstaller;

  final Future<String> Function() _currentVersionLoader;
  final Future<AppUpdateRelease> Function() _latestReleaseLoader;
  final Future<AppUpdateTarget> Function() _targetResolver;
  final AppUpdateAsset Function({
    required AppUpdateRelease release,
    required AppUpdateTarget target,
  })
  _assetSelector;
  final Future<File> Function(AppUpdateAsset asset)? _assetDownloader;
  final Future<File> Function(
    AppUpdateAsset asset, {
    AppUpdateDownloadProgressCallback? onProgress,
  })?
  _assetDownloaderWithProgress;
  final Future<void> Function({
    required AppUpdateAsset asset,
    required File file,
  })
  _downloadedAssetInstaller;

  String? _currentVersion;
  AppUpdateRelease? _latestRelease;
  AppUpdateAsset? _selectedAsset;
  AppUpdateCheckPhase _phase = AppUpdateCheckPhase.idle;
  AppUpdateApplyPhase _applyPhase = AppUpdateApplyPhase.idle;
  String? _lastError;
  String? _applyMessage;
  File? _downloadedAssetFile;
  int _downloadReceivedBytes = 0;
  int? _downloadTotalBytes;
  int _lastNotifiedBytes = 0;
  int _lastNotifiedPercent = -1;
  bool _initialized = false;
  bool _disposed = false;

  String? get currentVersion => _currentVersion;
  AppUpdateRelease? get latestRelease => _latestRelease;
  AppUpdateAsset? get selectedAsset => _selectedAsset;
  AppUpdateCheckPhase get phase => _phase;
  AppUpdateApplyPhase get applyPhase => _applyPhase;
  String? get lastError => _lastError;
  String? get applyMessage => _applyMessage;
  String? get downloadedAssetPath => _downloadedAssetFile?.path;
  int get downloadReceivedBytes => _downloadReceivedBytes;
  int? get downloadTotalBytes => _downloadTotalBytes;

  bool get isChecking => _phase == AppUpdateCheckPhase.checking;
  bool get isUpdateAvailable => _phase == AppUpdateCheckPhase.updateAvailable;
  bool get isUpToDate => _phase == AppUpdateCheckPhase.upToDate;
  bool get hasFailure => _phase == AppUpdateCheckPhase.failed;
  bool get isApplying => _applyPhase == AppUpdateApplyPhase.applying;
  bool get isDownloading =>
      _applyPhase == AppUpdateApplyPhase.applying &&
      _downloadedAssetFile == null;
  bool get isInstalling =>
      _applyPhase == AppUpdateApplyPhase.applying &&
      _downloadedAssetFile != null;
  bool get hasApplyFailure => _applyPhase == AppUpdateApplyPhase.failed;

  double? get downloadProgress {
    if (!isDownloading) {
      return null;
    }
    final total = _downloadTotalBytes ?? _selectedAsset?.size;
    if (total == null || total <= 0) {
      return null;
    }
    return (_downloadReceivedBytes / total).clamp(0.0, 1.0);
  }

  bool get canInstallDownloadedUpdate {
    final asset = _selectedAsset;
    return _phase == AppUpdateCheckPhase.updateAvailable &&
        (_applyPhase == AppUpdateApplyPhase.readyToInstall ||
            _applyPhase == AppUpdateApplyPhase.failed) &&
        _downloadedAssetFile != null &&
        asset != null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    try {
      _currentVersion = await _currentVersionLoader();
    } catch (_) {
      _currentVersion = null;
    }
    _notifySafely();
  }

  Future<void> checkForUpdates() async {
    if (_phase == AppUpdateCheckPhase.checking ||
        _applyPhase == AppUpdateApplyPhase.applying) {
      return;
    }
    _phase = AppUpdateCheckPhase.checking;
    _lastError = null;
    _selectedAsset = null;
    _downloadedAssetFile = null;
    _downloadReceivedBytes = 0;
    _downloadTotalBytes = null;
    _applyPhase = AppUpdateApplyPhase.idle;
    _applyMessage = null;
    _notifySafely();

    try {
      final currentVersion = _currentVersion ?? await _currentVersionLoader();
      if (_currentVersion != currentVersion) {
        _currentVersion = currentVersion;
      }
      final release = await _latestReleaseLoader();
      _latestRelease = release;
      final installed = AppSemanticVersion.parse(currentVersion);
      final latest = AppSemanticVersion.parse(release.version);
      if (latest.compareTo(installed) > 0) {
        final target = await _targetResolver();
        _selectedAsset = _assetSelector(release: release, target: target);
        _phase = AppUpdateCheckPhase.updateAvailable;
      } else {
        _phase = AppUpdateCheckPhase.upToDate;
      }
      _lastError = null;
    } catch (error) {
      _phase = AppUpdateCheckPhase.failed;
      _lastError = _formatError(error);
    }

    _notifySafely();
  }

  Future<void> applyUpdate() async {
    if (_applyPhase == AppUpdateApplyPhase.applying) {
      return;
    }
    final release = _latestRelease;
    final asset = _selectedAsset;
    if (_phase != AppUpdateCheckPhase.updateAvailable ||
        release == null ||
        asset == null) {
      _applyPhase = AppUpdateApplyPhase.failed;
      _applyMessage = 'No applicable update asset is available.';
      _notifySafely();
      return;
    }

    _downloadedAssetFile = null;
    _downloadReceivedBytes = 0;
    _downloadTotalBytes = asset.size > 0 ? asset.size : null;
    _lastNotifiedBytes = 0;
    _lastNotifiedPercent = -1;
    _applyPhase = AppUpdateApplyPhase.applying;
    _applyMessage = null;
    _notifySafely();

    try {
      final file = _assetDownloaderWithProgress != null
          ? await _assetDownloaderWithProgress(
              asset,
              onProgress: _handleDownloadProgress,
            )
          : await _assetDownloader!(asset);
      _downloadedAssetFile = file;
      if (_shouldOpenAfterDownload(asset)) {
        _notifySafely();
        await _downloadedAssetInstaller(asset: asset, file: file);
      }
      _applyPhase = AppUpdateApplyPhase.readyToInstall;
      _applyMessage = file.path;
    } catch (error) {
      _applyPhase = AppUpdateApplyPhase.failed;
      _applyMessage = _formatError(error);
    } finally {
      _downloadReceivedBytes = 0;
      _downloadTotalBytes = null;
    }

    _notifySafely();
  }

  Future<void> installDownloadedUpdate() async {
    if (_applyPhase == AppUpdateApplyPhase.applying) {
      return;
    }
    final asset = _selectedAsset;
    final file = _downloadedAssetFile;
    if (asset == null || file == null) {
      _applyPhase = AppUpdateApplyPhase.failed;
      _applyMessage = 'No downloaded update file is available.';
      _notifySafely();
      return;
    }

    if (!await file.exists()) {
      _downloadedAssetFile = null;
      _applyPhase = AppUpdateApplyPhase.idle;
      _applyMessage = fileNotFoundMessage;
      _notifySafely();
      return;
    }

    _applyPhase = AppUpdateApplyPhase.applying;
    _applyMessage = null;
    _notifySafely();

    try {
      await _downloadedAssetInstaller(asset: asset, file: file);
      _applyPhase = AppUpdateApplyPhase.readyToInstall;
      _applyMessage = file.path;
    } catch (error) {
      _applyPhase = AppUpdateApplyPhase.failed;
      _applyMessage = _formatError(error);
    }

    _notifySafely();
  }

  void _handleDownloadProgress(int receivedBytes, int? totalBytes) {
    if (_disposed ||
        _applyPhase != AppUpdateApplyPhase.applying ||
        _downloadedAssetFile != null) {
      return;
    }
    _downloadReceivedBytes = receivedBytes;
    if (totalBytes != null && totalBytes > 0) {
      _downloadTotalBytes = totalBytes;
    }
    final effectiveTotal = _downloadTotalBytes ?? _selectedAsset?.size;
    if (effectiveTotal != null && effectiveTotal > 0) {
      final percent = ((receivedBytes * 100) ~/ effectiveTotal).clamp(0, 100);
      if (percent != _lastNotifiedPercent || receivedBytes >= effectiveTotal) {
        _lastNotifiedPercent = percent;
        _lastNotifiedBytes = receivedBytes;
        _notifySafely();
      }
      return;
    }
    if (receivedBytes == 0 || receivedBytes - _lastNotifiedBytes >= 256 * 1024) {
      _lastNotifiedBytes = receivedBytes;
      _notifySafely();
    }
  }

  String _formatError(Object error) {
    if (error is StateError) {
      return error.message;
    }
    if (error is FormatException) {
      return error.message;
    }
    if (error is HttpException) {
      return error.message;
    }
    return error.toString();
  }

  bool _shouldOpenAfterDownload(AppUpdateAsset asset) {
    return asset.platform == 'android' && asset.format == 'apk';
  }
}
