import 'dart:io';

import 'package:flutter/services.dart';

class AndroidSharedStorageAccess {
  const AndroidSharedStorageAccess({
    MethodChannel channel = const MethodChannel('landa/network'),
    bool Function()? isAndroidProvider,
    void Function(String message)? log,
  }) : _channel = channel,
       _isAndroidProvider = isAndroidProvider,
       _log = log;

  final MethodChannel _channel;
  final bool Function()? _isAndroidProvider;
  final void Function(String message)? _log;

  Future<bool> hasAccess() async {
    if (!_isAndroid) {
      return true;
    }

    try {
      final granted = await _channel.invokeMethod<bool>(
        'canAccessSharedStorage',
      );
      return granted ?? false;
    } catch (error) {
      _log?.call('Failed to check shared storage permission: $error');
      return false;
    }
  }

  Future<bool> requestAccess() async {
    if (!_isAndroid) {
      return true;
    }
    if (await hasAccess()) {
      return true;
    }

    try {
      await _channel.invokeMethod<void>('requestSharedStorageAccess');
    } catch (error) {
      _log?.call('Failed to request shared storage permission: $error');
    }

    return hasAccess();
  }

  bool get _isAndroid => _isAndroidProvider?.call() ?? Platform.isAndroid;
}
