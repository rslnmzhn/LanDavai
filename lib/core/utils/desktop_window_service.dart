import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

class DesktopWindowService {
  static const MethodChannel _channel = MethodChannel('landa/network');

  Future<void> setMinimizeToTrayEnabled(bool enabled) async {
    if (!Platform.isWindows && !Platform.isLinux) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'setMinimizeToTrayEnabled',
        <String, Object?>{'enabled': enabled},
      );
    } catch (error) {
      developer.log(
        'Failed to configure minimize-to-tray mode: $error',
        name: 'DesktopWindowService',
      );
    }
  }
}
