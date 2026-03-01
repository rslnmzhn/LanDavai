import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

class AppNotificationService {
  AppNotificationService._();

  static final AppNotificationService instance = AppNotificationService._();
  static const MethodChannel _channel = MethodChannel('landa/network');

  Future<void> initialize() async {}

  Future<void> showDownloadAttemptNotification({
    required String requesterName,
    required String shareLabel,
    required int requestedFilesCount,
  }) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'showDownloadAttemptNotification',
        <String, Object?>{
          'requesterName': requesterName,
          'shareLabel': shareLabel,
          'requestedFilesCount': requestedFilesCount,
        },
      );
    } catch (error) {
      developer.log(
        'Failed to show download-attempt notification: $error',
        name: 'AppNotificationService',
      );
    }
  }

  Future<void> showFriendRequestNotification({
    required String requesterName,
  }) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'showFriendRequestNotification',
        <String, Object?>{'requesterName': requesterName},
      );
    } catch (error) {
      developer.log(
        'Failed to show friend-request notification: $error',
        name: 'AppNotificationService',
      );
    }
  }
}
