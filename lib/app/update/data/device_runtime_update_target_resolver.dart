import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../domain/app_update_models.dart';

class DeviceRuntimeUpdateTargetResolver {
  DeviceRuntimeUpdateTargetResolver({DeviceInfoPlugin? deviceInfoPlugin})
    : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfoPlugin;

  Future<AppUpdateTarget> resolve() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      final preferredAbis = androidInfo.supportedAbis
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      return AppUpdateTarget(
        platform: AppUpdateRuntimePlatform.android,
        archPreferences: preferredAbis.isEmpty
            ? const <String>['arm64-v8a', 'armeabi-v7a', 'x86_64']
            : preferredAbis,
      );
    }
    if (Platform.isWindows) {
      return const AppUpdateTarget(
        platform: AppUpdateRuntimePlatform.windows,
        archPreferences: <String>['x86_64'],
      );
    }
    if (Platform.isLinux) {
      return const AppUpdateTarget(
        platform: AppUpdateRuntimePlatform.linux,
        archPreferences: <String>['x86_64'],
      );
    }
    if (Platform.isMacOS) {
      return const AppUpdateTarget(
        platform: AppUpdateRuntimePlatform.macos,
        archPreferences: <String>['x86_64', 'arm64'],
      );
    }
    return const AppUpdateTarget(
      platform: AppUpdateRuntimePlatform.unsupported,
      archPreferences: <String>[],
    );
  }
}
