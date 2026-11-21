import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppUpdateStorageService {
  AppUpdateStorageService({Future<Directory> Function()? updateDirectoryResolver})
    : _updateDirectoryResolver = updateDirectoryResolver;

  final Future<Directory> Function()? _updateDirectoryResolver;

  Future<File> createTargetFile(String fileName) async {
    final safeFileName = p.basename(fileName.trim());
    final directory = _updateDirectoryResolver != null
        ? await _updateDirectoryResolver()
        : await _resolveUpdateDirectory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, safeFileName.isEmpty ? 'update.bin' : safeFileName));
  }

  Future<Directory> _resolveUpdateDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null && (Platform.isWindows || Platform.isLinux)) {
      return Directory(p.join(downloads.path, 'Landa', 'updates'));
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Landa', 'updates'));
  }
}
