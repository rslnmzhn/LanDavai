import 'dart:developer' as developer;
import 'dart:io';

class IncomingTempSweepResult {
  const IncomingTempSweepResult({
    required this.filesDeleted,
    required this.bytesFreed,
  });

  final int filesDeleted;
  final int bytesFreed;
}

/// Deletes stale files left behind in the Android `incoming_temp` staging
/// directory by interrupted or failed transfers. Files younger than
/// [minFileAge] are preserved so a concurrently running transfer is not
/// destroyed.
class IncomingTempSweeper {
  const IncomingTempSweeper({this.minFileAge = const Duration(hours: 1)});

  final Duration minFileAge;

  Future<IncomingTempSweepResult> sweep(Directory directory) async {
    if (!await directory.exists()) {
      return const IncomingTempSweepResult(filesDeleted: 0, bytesFreed: 0);
    }

    final cutoff = DateTime.now().subtract(minFileAge);
    var filesDeleted = 0;
    var bytesFreed = 0;
    final subDirectories = <Directory>[];

    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Directory) {
          subDirectories.add(entity);
          continue;
        }
        if (entity is! File) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file ||
              stat.modified.isAfter(cutoff)) {
            continue;
          }
          await entity.delete();
          filesDeleted += 1;
          bytesFreed += stat.size;
        } catch (error) {
          developer.log(
            'Failed to sweep stale incoming temp file '
            '${entity.path}: $error',
            name: 'IncomingTempSweeper',
          );
        }
      }
    } catch (error) {
      developer.log(
        'Failed to sweep incoming temp directory ${directory.path}: $error',
        name: 'IncomingTempSweeper',
      );
      return IncomingTempSweepResult(
        filesDeleted: filesDeleted,
        bytesFreed: bytesFreed,
      );
    }

    // Best-effort removal of directories emptied by the sweep, deepest first.
    subDirectories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final subDirectory in subDirectories) {
      try {
        final stat = await subDirectory.stat();
        if (stat.modified.isAfter(cutoff)) {
          continue;
        }
        // Non-recursive delete: fails when the directory is not empty,
        // which is exactly the behavior we want here.
        await subDirectory.delete();
      } catch (_) {
        // Not empty anymore or locked; leave it in place.
      }
    }

    return IncomingTempSweepResult(
      filesDeleted: filesDeleted,
      bytesFreed: bytesFreed,
    );
  }
}
