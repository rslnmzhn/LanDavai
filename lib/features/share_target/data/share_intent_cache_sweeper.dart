import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../transfer/data/incoming_temp_sweeper.dart';

/// Removes stale share-intent staging files left in the platform cache
/// directory (`<cache>/share_intent`) by interrupted or discarded Android
/// share flows. Complements the consume-time discard: files orphaned by an
/// app kill or a crash are cleaned on a later startup.
class ShareIntentCacheSweeper {
  const ShareIntentCacheSweeper({
    this.minFileAge = const Duration(hours: 24),
    Future<Directory?> Function()? resolveCacheDirectory,
  }) : _resolveCacheDirectory = resolveCacheDirectory;

  /// Staging copies are short-lived by design; only clearly abandoned files
  /// are swept so an in-flight share flow is never disturbed.
  final Duration minFileAge;
  final Future<Directory?> Function()? _resolveCacheDirectory;

  Future<IncomingTempSweepResult> sweepStaleFiles() async {
    final cacheDirectory =
        await (_resolveCacheDirectory ?? defaultResolveCacheDirectory)();
    if (cacheDirectory == null) {
      return const IncomingTempSweepResult(filesDeleted: 0, bytesFreed: 0);
    }

    final shareIntentDirectory = Directory(
      // Must stay in sync with the platform staging literal in
      // MainActivity.kt (File(cacheDir, "share_intent")); drift fails safe
      // but silently.
      p.join(cacheDirectory.path, 'share_intent'),
    );
    return IncomingTempSweeper(
      minFileAge: minFileAge,
    ).sweep(shareIntentDirectory);
  }

  /// Returns the platform cache directory on Android; null elsewhere, where
  /// the share-intent staging flow does not exist.
  static Future<Directory?> defaultResolveCacheDirectory() async {
    if (!Platform.isAndroid) {
      return null;
    }
    return getTemporaryDirectory();
  }
}
