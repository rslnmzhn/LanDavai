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

  Future<void> showSharedRecacheProgressNotification({
    required int processedCaches,
    required int totalCaches,
    required String currentCacheLabel,
    int? processedFiles,
    int? totalFiles,
    int? etaSeconds,
    String? currentFileLabel,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final payload = <String, Object?>{
        'processedCaches': processedCaches,
        'totalCaches': totalCaches,
        'currentCacheLabel': currentCacheLabel,
      };
      if (processedFiles != null) {
        payload['processedFiles'] = processedFiles;
      }
      if (totalFiles != null) {
        payload['totalFiles'] = totalFiles;
      }
      if (etaSeconds != null) {
        payload['etaSeconds'] = etaSeconds;
      }
      if (currentFileLabel != null) {
        payload['currentFileLabel'] = currentFileLabel;
      }
      await _channel.invokeMethod<void>(
        'showSharedRecacheProgressNotification',
        payload,
      );
    } catch (error) {
      developer.log(
        'Failed to show shared recache progress notification: $error',
        name: 'AppNotificationService',
      );
    }
  }

  Future<void> showSharedRecacheCompletedNotification({
    required int beforeFiles,
    required int afterFiles,
  }) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'showSharedRecacheCompletedNotification',
        <String, Object?>{'beforeFiles': beforeFiles, 'afterFiles': afterFiles},
      );
    } catch (error) {
      if (Platform.isWindows) {
        await _showWindowsFallbackRecacheNotification(
          beforeFiles: beforeFiles,
          afterFiles: afterFiles,
        );
      }
      developer.log(
        'Failed to show shared recache completion notification: $error',
        name: 'AppNotificationService',
      );
    }
  }

  Future<void> _showWindowsFallbackRecacheNotification({
    required int beforeFiles,
    required int afterFiles,
  }) async {
    try {
      await _channel.invokeMethod<void>('showDownloadAttemptNotification', <
        String,
        Object?
      >{
        'requesterName': 'Shared cache update',
        'shareLabel':
            'Before cache: $beforeFiles files, after re-cache: $afterFiles files.',
        'requestedFilesCount': 0,
      });
    } catch (_) {
      // Best-effort fallback.
    }
  }
}
