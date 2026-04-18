import 'package:flutter/foundation.dart';

import '../domain/app_update_models.dart';

class AppUpdateBoundary extends ChangeNotifier {
  AppUpdateBoundary({
    required Future<String> Function() currentVersionLoader,
    required Future<AppUpdateRelease> Function() latestReleaseLoader,
  }) : _currentVersionLoader = currentVersionLoader,
       _latestReleaseLoader = latestReleaseLoader;

  final Future<String> Function() _currentVersionLoader;
  final Future<AppUpdateRelease> Function() _latestReleaseLoader;

  String? _currentVersion;
  AppUpdateRelease? _latestRelease;
  AppUpdateCheckPhase _phase = AppUpdateCheckPhase.idle;
  String? _lastError;
  bool _initialized = false;

  String? get currentVersion => _currentVersion;
  AppUpdateRelease? get latestRelease => _latestRelease;
  AppUpdateCheckPhase get phase => _phase;
  String? get lastError => _lastError;

  bool get isChecking => _phase == AppUpdateCheckPhase.checking;
  bool get isUpdateAvailable => _phase == AppUpdateCheckPhase.updateAvailable;
  bool get isUpToDate => _phase == AppUpdateCheckPhase.upToDate;
  bool get hasFailure => _phase == AppUpdateCheckPhase.failed;

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
    notifyListeners();

    try {
      final release = await _latestReleaseLoader();
      _latestRelease = release;
      final installed = AppSemanticVersion.parse(currentVersion);
      final latest = AppSemanticVersion.parse(release.version);
      _phase = latest.compareTo(installed) > 0
          ? AppUpdateCheckPhase.updateAvailable
          : AppUpdateCheckPhase.upToDate;
      _lastError = null;
    } catch (error) {
      _phase = AppUpdateCheckPhase.failed;
      _lastError = error.toString();
    }

    notifyListeners();
  }
}
