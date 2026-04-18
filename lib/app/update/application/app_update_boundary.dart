import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/app_update_models.dart';

class AppUpdateBoundary extends ChangeNotifier {
  AppUpdateBoundary({
    required Future<String> Function() currentVersionLoader,
    required Future<AppUpdateRelease> Function() latestReleaseLoader,
    required Future<AppUpdateTarget> Function() targetResolver,
    required AppUpdateAsset Function({
      required AppUpdateRelease release,
      required AppUpdateTarget target,
    })
    assetSelector,
    required Future<File> Function(AppUpdateAsset asset) assetDownloader,
    required Future<void> Function({
      required AppUpdateAsset asset,
      required File file,
    })
    downloadedAssetOpener,
  }) : _currentVersionLoader = currentVersionLoader,
       _latestReleaseLoader = latestReleaseLoader,
       _targetResolver = targetResolver,
       _assetSelector = assetSelector,
       _assetDownloader = assetDownloader,
       _downloadedAssetOpener = downloadedAssetOpener;

  final Future<String> Function() _currentVersionLoader;
  final Future<AppUpdateRelease> Function() _latestReleaseLoader;
  final Future<AppUpdateTarget> Function() _targetResolver;
  final AppUpdateAsset Function({
    required AppUpdateRelease release,
    required AppUpdateTarget target,
  })
  _assetSelector;
  final Future<File> Function(AppUpdateAsset asset) _assetDownloader;
  final Future<void> Function({
    required AppUpdateAsset asset,
    required File file,
  })
  _downloadedAssetOpener;

  String? _currentVersion;
  AppUpdateRelease? _latestRelease;
  AppUpdateAsset? _selectedAsset;
  AppUpdateCheckPhase _phase = AppUpdateCheckPhase.idle;
  AppUpdateApplyPhase _applyPhase = AppUpdateApplyPhase.idle;
  String? _lastError;
  String? _applyMessage;
  bool _initialized = false;

  String? get currentVersion => _currentVersion;
  AppUpdateRelease? get latestRelease => _latestRelease;
  AppUpdateAsset? get selectedAsset => _selectedAsset;
  AppUpdateCheckPhase get phase => _phase;
  AppUpdateApplyPhase get applyPhase => _applyPhase;
  String? get lastError => _lastError;
  String? get applyMessage => _applyMessage;

  bool get isChecking => _phase == AppUpdateCheckPhase.checking;
  bool get isUpdateAvailable => _phase == AppUpdateCheckPhase.updateAvailable;
  bool get isUpToDate => _phase == AppUpdateCheckPhase.upToDate;
  bool get hasFailure => _phase == AppUpdateCheckPhase.failed;
  bool get isApplying => _applyPhase == AppUpdateApplyPhase.applying;
  bool get hasApplyFailure => _applyPhase == AppUpdateApplyPhase.failed;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _currentVersion = await _currentVersionLoader();
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    final currentVersion = _currentVersion ?? await _currentVersionLoader();
    if (_currentVersion != currentVersion) {
      _currentVersion = currentVersion;
    }
    _phase = AppUpdateCheckPhase.checking;
    _lastError = null;
    _selectedAsset = null;
    _applyPhase = AppUpdateApplyPhase.idle;
    _applyMessage = null;
    notifyListeners();

    try {
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
      _lastError = error.toString();
    }

    notifyListeners();
  }

  Future<void> applyUpdate() async {
    final release = _latestRelease;
    final asset = _selectedAsset;
    if (_phase != AppUpdateCheckPhase.updateAvailable ||
        release == null ||
        asset == null) {
      _applyPhase = AppUpdateApplyPhase.failed;
      _applyMessage = 'No applicable update asset is available.';
      notifyListeners();
      return;
    }

    _applyPhase = AppUpdateApplyPhase.applying;
    _applyMessage = null;
    notifyListeners();

    try {
      final file = await _assetDownloader(asset);
      await _downloadedAssetOpener(asset: asset, file: file);
      _applyPhase = AppUpdateApplyPhase.readyToInstall;
      _applyMessage = file.path;
    } catch (error) {
      _applyPhase = AppUpdateApplyPhase.failed;
      _applyMessage = error.toString();
    }

    notifyListeners();
  }
}
