import 'dart:io';

class TransferFailedFileCleanup {
  const TransferFailedFileCleanup();

  Future<void> cleanupSavedFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> cleanupInProgressFile(String? path) async {
    if (path == null) {
      return;
    }
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
