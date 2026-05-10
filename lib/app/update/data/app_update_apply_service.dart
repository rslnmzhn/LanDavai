import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/utils/path_opener.dart';
import '../domain/app_update_models.dart';

class AppUpdateApplyService {
  AppUpdateApplyService({required PathOpener pathOpener})
    : _pathOpener = pathOpener;

  static const MethodChannel _androidUpdateChannel = MethodChannel(
    'landa/network',
  );

  final PathOpener _pathOpener;

  Future<void> openDownloadedAsset({
    required AppUpdateAsset asset,
    required File file,
  }) async {
    if (asset.format == 'apk' && Platform.isAndroid) {
      await _androidUpdateChannel.invokeMethod<void>('installApkUpdate', {
        'path': file.path,
      });
      return;
    }
    if (asset.format == 'appimage' && Platform.isLinux) {
      await Process.run('chmod', <String>['+x', file.path]);
    }
    await _pathOpener.openPath(file.path);
  }
}
