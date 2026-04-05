import 'dart:io';

import 'package:path/path.dart' as p;

class SingleInstanceGuardHandle {
  SingleInstanceGuardHandle._({
    required this.acquired,
    required this.shouldBlockStartup,
    String? lockKey,
    RandomAccessFile? lockFile,
  }) : _lockKey = lockKey,
       _lockFile = lockFile;

  factory SingleInstanceGuardHandle.acquired({
    required String lockKey,
    required RandomAccessFile lockFile,
  }) {
    return SingleInstanceGuardHandle._(
      acquired: true,
      shouldBlockStartup: false,
      lockKey: lockKey,
      lockFile: lockFile,
    );
  }

  factory SingleInstanceGuardHandle.notEnforced() {
    return SingleInstanceGuardHandle._(
      acquired: false,
      shouldBlockStartup: false,
    );
  }

  factory SingleInstanceGuardHandle.blocked() {
    return SingleInstanceGuardHandle._(
      acquired: false,
      shouldBlockStartup: true,
    );
  }

  final bool acquired;
  final bool shouldBlockStartup;
  final String? _lockKey;
  final RandomAccessFile? _lockFile;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final lockFile = _lockFile;
    final lockKey = _lockKey;
    if (lockFile != null) {
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
    if (lockKey != null) {
      SingleInstanceGuard._releaseInProcessLock(lockKey);
    }
  }
}

class SingleInstanceGuard {
  const SingleInstanceGuard({bool Function()? desktopPlatformResolver})
    : _desktopPlatformResolver = desktopPlatformResolver;

  static const String defaultLockFileName = 'landa_single_instance.lock';
  static final Set<String> _heldLockKeys = <String>{};
  final bool Function()? _desktopPlatformResolver;

  Future<SingleInstanceGuardHandle> acquire({
    Directory? lockDirectory,
    String lockFileName = defaultLockFileName,
  }) async {
    if (!_isDesktopPlatform) {
      return SingleInstanceGuardHandle.notEnforced();
    }

    final directory = lockDirectory ?? Directory.systemTemp;
    final file = File(p.join(directory.path, lockFileName));
    await file.parent.create(recursive: true);
    final lockKey = _normalizeLockKey(file.path);
    if (!_tryAcquireInProcessLock(lockKey)) {
      return SingleInstanceGuardHandle.blocked();
    }
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      return SingleInstanceGuardHandle.acquired(
        lockKey: lockKey,
        lockFile: handle,
      );
    } on FileSystemException {
      await handle.close();
      _releaseInProcessLock(lockKey);
      return SingleInstanceGuardHandle.blocked();
    }
  }

  bool get _isDesktopPlatform =>
      _desktopPlatformResolver?.call() ??
      (Platform.isWindows || Platform.isLinux);

  static bool _tryAcquireInProcessLock(String lockKey) {
    if (_heldLockKeys.contains(lockKey)) {
      return false;
    }
    _heldLockKeys.add(lockKey);
    return true;
  }

  static void _releaseInProcessLock(String lockKey) {
    _heldLockKeys.remove(lockKey);
  }

  String _normalizeLockKey(String filePath) {
    final absolute = p.normalize(p.absolute(filePath));
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }
}
