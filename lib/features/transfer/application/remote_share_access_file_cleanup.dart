import 'dart:io';

Future<void> cleanupRemoteShareAccessDirectory(Directory directory) async {
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } catch (_) {}
}
