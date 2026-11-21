import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/utils/path_opener.dart';
import '../domain/app_update_models.dart';

class AppUpdateApplyService {
  AppUpdateApplyService({
    required PathOpener pathOpener,
    bool? isAndroidOverride,
    bool? isLinuxOverride,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    processRunner,
    Future<void> Function(String path)? androidApkInstaller,
  }) : _pathOpener = pathOpener,
       _isAndroidOverride = isAndroidOverride,
       _isLinuxOverride = isLinuxOverride,
       _processRunner = processRunner ?? Process.run,
       _androidApkInstaller = androidApkInstaller;

  static const MethodChannel _androidUpdateChannel = MethodChannel(
    'landa/network',
  );

  final PathOpener _pathOpener;
  final bool? _isAndroidOverride;
  final bool? _isLinuxOverride;
  final Future<ProcessResult> Function(String executable, List<String> arguments)
  _processRunner;
  final Future<void> Function(String path)? _androidApkInstaller;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;
  bool get _isLinux => _isLinuxOverride ?? Platform.isLinux;

  Future<void> openDownloadedAsset({
    required AppUpdateAsset asset,
    required File file,
  }) async {
    if (asset.format == 'apk' && _isAndroid) {
      try {
        if (_androidApkInstaller != null) {
          await _androidApkInstaller(file.path);
        } else {
          await _androidUpdateChannel.invokeMethod<void>('installApkUpdate', {
            'path': file.path,
          });
        }
      } on PlatformException catch (error) {
        final message = error.message?.trim();
        throw StateError(
          (message != null && message.isNotEmpty) ? message : error.code,
        );
      }
      return;
    }
    if (asset.format == 'appimage' && _isLinux) {
      final chmodResult = await _processRunner('chmod', <String>[
        '+x',
        file.path,
      ]);
      if (chmodResult.exitCode != 0) {
        final stderrText = chmodResult.stderr.toString().trim();
        throw StateError(
          stderrText.isEmpty
              ? 'chmod +x failed with exit code ${chmodResult.exitCode}.'
              : stderrText,
        );
      }
      await _pathOpener.openContainingFolder(file.path);
      return;
    }
    try {
      await _pathOpener.openPath(file.path);
    } catch (_) {
      await _pathOpener.openContainingFolder(file.path);
    }
  }
}
