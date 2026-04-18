import 'dart:io';

import '../../../core/utils/path_opener.dart';
import '../domain/app_update_models.dart';

class AppUpdateApplyService {
  AppUpdateApplyService({required PathOpener pathOpener})
    : _pathOpener = pathOpener;

  final PathOpener _pathOpener;

  Future<void> openDownloadedAsset({
    required AppUpdateAsset asset,
    required File file,
  }) async {
    if (asset.format == 'appimage' && Platform.isLinux) {
      await Process.run('chmod', <String>['+x', file.path]);
    }
    await _pathOpener.openPath(file.path);
  }
}
