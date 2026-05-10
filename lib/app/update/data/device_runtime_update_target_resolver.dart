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
      final preferredAbis = _androidAbiPreferences(androidInfo);
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

  List<String> _androidAbiPreferences(AndroidDeviceInfo androidInfo) {
    final productAbis = <String>{
      ...androidInfo.supported64BitAbis
          .map(_normalizeAndroidAbi)
          .whereType<String>(),
      ...androidInfo.supported32BitAbis
          .map(_normalizeAndroidAbi)
          .whereType<String>(),
      ...androidInfo.supportedAbis
          .map(_normalizeAndroidAbi)
          .whereType<String>(),
    };
    final normalizedRuntimeAbis = _runtimeAbiCandidates()
        .where(productAbis.contains)
        .toList(growable: false);
    if (normalizedRuntimeAbis.isNotEmpty) {
      return normalizedRuntimeAbis;
    }
    return androidInfo.supportedAbis
        .map(_normalizeAndroidAbi)
        .where((value) => value != null)
        .cast<String>()
        .toList(growable: false);
  }

  List<String> _runtimeAbiCandidates() {
    final environmentValues = <String>[
      Platform.environment['ANDROID_ABI'] ?? '',
      Platform.environment['ANDROID_CPU_ABI'] ?? '',
      Platform.environment['ANDROID_CPU_ABI2'] ?? '',
      Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '',
    ];
    return environmentValues
        .map(_normalizeAndroidAbi)
        .where((value) => value != null)
        .cast<String>()
        .toSet()
        .toList(growable: false);
  }

  String? _normalizeAndroidAbi(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('-', '_');
    if (value.isEmpty) {
      return null;
    }
    if (value == 'armeabi_v7a' || value == 'armv7l' || value == 'arm') {
      return 'armeabi-v7a';
    }
    if (value == 'arm64_v8a' || value == 'aarch64' || value == 'arm64') {
      return 'arm64-v8a';
    }
    if (value == 'x86_64' || value == 'amd64') {
      return 'x86_64';
    }
    return null;
  }
}
