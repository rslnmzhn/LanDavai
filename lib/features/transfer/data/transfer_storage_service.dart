import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PreviewCacheCleanupResult {
  const PreviewCacheCleanupResult({
    required this.filesDeleted,
    required this.bytesFreed,
    required this.filesRemaining,
    required this.remainingBytes,
  });

  final int filesDeleted;
  final int bytesFreed;
  final int filesRemaining;
  final int remainingBytes;
}

class TransferStorageService {
  static const MethodChannel _platformChannel = MethodChannel('landa/network');

  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    if (Platform.isAndroid) {
      // Receive into app sandbox first, then publish to Downloads/Landa.
      final support = await getApplicationSupportDirectory();
      final target = Directory(
        p.join(support.path, appFolderName, 'incoming_temp'),
      );
      await target.create(recursive: true);
      return target;
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      final target = Directory(p.join(downloads.path, appFolderName));
      await target.create(recursive: true);
      return target;
    }

    final docs = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(docs.path, appFolderName, 'downloads'));
    await target.create(recursive: true);
    return target;
  }

  Future<Directory> resolvePreviewDirectory({
    String appFolderName = 'Landa',
  }) async {
    final support = await getApplicationSupportDirectory();
    final target = Directory(
      p.join(support.path, appFolderName, 'preview_cache'),
    );
    await target.create(recursive: true);
    return target;
  }

  Future<PreviewCacheCleanupResult> cleanupPreviewCache({
    required int maxSizeGb,
    required int maxAgeDays,
    String appFolderName = 'Landa',
  }) async {
    final directory = await resolvePreviewDirectory(
      appFolderName: appFolderName,
    );
    if (!await directory.exists()) {
      return const PreviewCacheCleanupResult(
        filesDeleted: 0,
        bytesFreed: 0,
        filesRemaining: 0,
        remainingBytes: 0,
      );
    }

    final entries = <_PreviewCacheEntry>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        entries.add(
          _PreviewCacheEntry(
            path: entity.path,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      } catch (_) {
        // Skip unreadable entries.
      }
    }

    var filesDeleted = 0;
    var bytesFreed = 0;
    final survivors = <_PreviewCacheEntry>[];

    final expiryCutoff = maxAgeDays > 0
        ? DateTime.now().subtract(Duration(days: maxAgeDays))
        : null;
    for (final entry in entries) {
      if (expiryCutoff != null && entry.modifiedAt.isBefore(expiryCutoff)) {
        final deleted = await _tryDeleteFile(entry.path);
        if (deleted) {
          filesDeleted += 1;
          bytesFreed += entry.sizeBytes;
          continue;
        }
      }
      survivors.add(entry);
    }

    final maxSizeBytes = maxSizeGb > 0 ? maxSizeGb * 1024 * 1024 * 1024 : null;
    var remainingBytes = survivors.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );

    if (maxSizeBytes != null && remainingBytes > maxSizeBytes) {
      survivors.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
      for (final entry in survivors) {
        if (remainingBytes <= maxSizeBytes) {
          break;
        }
        final deleted = await _tryDeleteFile(entry.path);
        if (!deleted) {
          continue;
        }
        filesDeleted += 1;
        bytesFreed += entry.sizeBytes;
        remainingBytes -= entry.sizeBytes;
        entry.deleted = true;
      }
    }

    final filesRemaining = survivors.where((entry) => !entry.deleted).length;
    if (remainingBytes < 0) {
      remainingBytes = 0;
    }

    return PreviewCacheCleanupResult(
      filesDeleted: filesDeleted,
      bytesFreed: bytesFreed,
      filesRemaining: filesRemaining,
      remainingBytes: remainingBytes,
    );
  }

  Future<bool> _tryDeleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Directory> resolveClipboardDirectory({
    String appFolderName = 'Landa',
  }) async {
    final support = await getApplicationSupportDirectory();
    final target = Directory(
      p.join(support.path, appFolderName, 'clipboard_cache'),
    );
    await target.create(recursive: true);
    return target;
  }

  Future<List<String>> publishToUserDownloads({
    required List<String> sourcePaths,
    required List<String> relativePaths,
    String appFolderName = 'Landa',
  }) async {
    if (sourcePaths.length != relativePaths.length) {
      throw ArgumentError('sourcePaths and relativePaths length mismatch.');
    }
    if (!Platform.isAndroid) {
      return sourcePaths;
    }

    final published = <String>[];
    for (var i = 0; i < sourcePaths.length; i += 1) {
      final sourcePath = sourcePaths[i];
      final relativePath = relativePaths[i];
      final destinationPath = await _platformChannel
          .invokeMethod<String>('copyFileToDownloads', <String, Object?>{
            'sourcePath': sourcePath,
            'relativePath': relativePath,
            'appFolderName': appFolderName,
          });
      if (destinationPath == null || destinationPath.trim().isEmpty) {
        throw StateError('Failed to publish file to Downloads: $relativePath');
      }
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
      published.add(destinationPath.trim());
    }
    return published;
  }

  Future<Directory?> resolveAndroidPublicDownloadsDirectory() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final rawPath = await _platformChannel.invokeMethod<String>(
        'getPublicDownloadsPath',
      );
      if (rawPath == null || rawPath.trim().isEmpty) {
        return null;
      }
      return Directory(rawPath.trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> showAndroidDownloadProgressNotification({
    required String requestId,
    required String senderName,
    required int receivedBytes,
    required int totalBytes,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _platformChannel.invokeMethod<void>(
        'showDownloadProgressNotification',
        <String, Object?>{
          'requestId': requestId,
          'senderName': senderName,
          'receivedBytes': receivedBytes,
          'totalBytes': totalBytes,
        },
      );
    } catch (error) {
      developer.log(
        'Failed to show Android progress notification: $error',
        name: 'TransferStorageService',
      );
    }
  }

  Future<void> showAndroidDownloadCompletedNotification({
    required String requestId,
    required List<String> savedPaths,
    required String directoryPath,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _platformChannel.invokeMethod<void>(
        'showDownloadCompletedNotification',
        <String, Object?>{
          'requestId': requestId,
          'savedPaths': savedPaths,
          'directoryPath': directoryPath,
        },
      );
    } catch (error) {
      developer.log(
        'Failed to show Android completion notification: $error',
        name: 'TransferStorageService',
      );
    }
  }

  Future<void> showAndroidDownloadFailedNotification({
    required String requestId,
    required String message,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _platformChannel.invokeMethod<void>(
        'showDownloadFailedNotification',
        <String, Object?>{'requestId': requestId, 'message': message},
      );
    } catch (error) {
      developer.log(
        'Failed to show Android failure notification: $error',
        name: 'TransferStorageService',
      );
    }
  }
}

class _PreviewCacheEntry {
  _PreviewCacheEntry({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
  bool deleted = false;
}
