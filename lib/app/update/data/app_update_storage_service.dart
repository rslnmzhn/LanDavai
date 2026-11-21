import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppUpdateStorageService {
  AppUpdateStorageService({Future<Directory> Function()? updateDirectoryResolver})
    : _updateDirectoryResolver = updateDirectoryResolver;

  final Future<Directory> Function()? _updateDirectoryResolver;

  Future<File> createTargetFile(String fileName) async {
    final rawBase = p.basename(fileName.trim());
    final safeFileName =
        (rawBase.isEmpty || rawBase == '.' || rawBase == '..')
        ? 'update.bin'
        : rawBase;
    final directory = _updateDirectoryResolver != null
        ? await _updateDirectoryResolver()
        : await _resolveUpdateDirectory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, safeFileName));
  }

  Future<Directory> _resolveUpdateDirectory() async {
    if (Platform.isWindows || Platform.isLinux) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          return Directory(p.join(downloads.path, 'Landa', 'updates'));
        }
      } catch (_) {
        // Fall back to application support directory when Downloads is unavailable.
      }
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Landa', 'updates'));
  }
}
