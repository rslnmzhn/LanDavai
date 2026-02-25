import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TransferStorageService {
  static const MethodChannel _platformChannel = MethodChannel('landa/network');

  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'LanDa',
  }) async {
    if (Platform.isAndroid) {
      // Receive into app sandbox first, then publish to Downloads/LanDa.
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

  Future<List<String>> publishToUserDownloads({
    required List<String> sourcePaths,
    required List<String> relativePaths,
    String appFolderName = 'LanDa',
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
}
