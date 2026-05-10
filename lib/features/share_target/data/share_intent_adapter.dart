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
}
