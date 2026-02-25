import 'dart:io';

import 'package:open_filex/open_filex.dart';

class PathOpener {
  Future<void> openContainingFolder(String path) async {
    final target = _resolveFolderTarget(path);
    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>[target]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', <String>[target]);
      return;
    }

    final result = await OpenFilex.open(target);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  String _resolveFolderTarget(String path) {
    final entity = FileSystemEntity.typeSync(path, followLinks: false);
    if (entity == FileSystemEntityType.directory) {
      return path;
    }
    return File(path).parent.path;
  }
}
