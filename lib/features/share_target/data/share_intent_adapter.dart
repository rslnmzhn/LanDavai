import 'dart:io';

import 'package:flutter/services.dart';

class ShareIntentAdapter {
  static const MethodChannel _channel = MethodChannel('landa/share_intent');

  Future<List<String>> consumePendingSharedFiles() async {
    if (!Platform.isAndroid) {
      return const <String>[];
    }

    final paths = await _channel.invokeListMethod<String>('getSharedFiles');
    return paths ?? const <String>[];
  }

  /// Best-effort deletion of consumed staging copies; the platform side
  /// validates that only files inside its own share_intent cache are
  /// removed. Returns how many files were actually deleted.
  Future<int> discardPendingSharedFiles(List<String> paths) async {
    if (!Platform.isAndroid || paths.isEmpty) {
      return 0;
    }

    final deleted = await _channel.invokeMethod<int>(
      'discardSharedFiles',
      paths,
    );
    return deleted ?? 0;
  }
}
