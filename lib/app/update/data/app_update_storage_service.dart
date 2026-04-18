import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppUpdateStorageService {
  Future<File> createTargetFile(String fileName) async {
    final directory = await _resolveUpdateDirectory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
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
