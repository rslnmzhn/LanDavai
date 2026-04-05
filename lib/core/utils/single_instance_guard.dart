import 'dart:io';

import 'package:path/path.dart' as p;

class SingleInstanceGuardHandle {
  const SingleInstanceGuardHandle._({
    required this.acquired,
    RandomAccessFile? lockFile,
  }) : _lockFile = lockFile;

  factory SingleInstanceGuardHandle.acquired(RandomAccessFile lockFile) {
    return SingleInstanceGuardHandle._(acquired: true, lockFile: lockFile);
  }

  factory SingleInstanceGuardHandle.skipped() {
    return const SingleInstanceGuardHandle._(acquired: false);
  }

  final bool acquired;
  final RandomAccessFile? _lockFile;

  Future<void> dispose() async {
    final lockFile = _lockFile;
    if (lockFile == null) {
      return;
    }
    try {
      await lockFile.unlock();
    } catch (_) {
      // Best effort: process teardown also releases OS-level file locks.
    }
    try {
      await lockFile.close();
    } catch (_) {
      // Best effort cleanup only.
    }
  }
}

class SingleInstanceGuard {
  const SingleInstanceGuard();

  static const String defaultLockFileName = 'landa_single_instance.lock';

  Future<SingleInstanceGuardHandle> acquire({
    Directory? lockDirectory,
    String lockFileName = defaultLockFileName,
  }) async {
    if (!_isDesktopPlatform) {
      return SingleInstanceGuardHandle.skipped();
    }

    final directory = lockDirectory ?? Directory.systemTemp;
    final file = File(p.join(directory.path, lockFileName));
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      return SingleInstanceGuardHandle.acquired(handle);
    } on FileSystemException {
      await handle.close();
      return SingleInstanceGuardHandle.skipped();
    }
  }

  bool get _isDesktopPlatform => Platform.isWindows || Platform.isLinux;
}
