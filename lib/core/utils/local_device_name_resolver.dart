import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class LocalDeviceNameResolver {
  LocalDeviceNameResolver({
    DeviceInfoPlugin? deviceInfoPlugin,
    String Function()? localHostnameProvider,
    bool? isAndroidOverride,
    bool? isIosOverride,
    bool? isWindowsOverride,
    bool? isLinuxOverride,
    bool? isMacOsOverride,
  }) : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin(),
       _localHostnameProvider = localHostnameProvider,
       _isAndroidOverride = isAndroidOverride,
       _isIosOverride = isIosOverride,
       _isWindowsOverride = isWindowsOverride,
       _isLinuxOverride = isLinuxOverride,
       _isMacOsOverride = isMacOsOverride;

  final DeviceInfoPlugin _deviceInfoPlugin;
  final String Function()? _localHostnameProvider;
  final bool? _isAndroidOverride;
  final bool? _isIosOverride;
  final bool? _isWindowsOverride;
  final bool? _isLinuxOverride;
  final bool? _isMacOsOverride;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;
  bool get _isIos => _isIosOverride ?? Platform.isIOS;
  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;
  bool get _isLinux => _isLinuxOverride ?? Platform.isLinux;
  bool get _isMacOs => _isMacOsOverride ?? Platform.isMacOS;

  Future<String> resolve() async {
    final hostname = (_localHostnameProvider?.call() ?? Platform.localHostname)
        .trim();

    if (_isAndroid) {
      try {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        final resolved = _resolveAndroidName(
          deviceName: androidInfo.name,
          manufacturer: androidInfo.manufacturer,
          model: androidInfo.model,
          brand: androidInfo.brand,
        );
        if (resolved != null) {
          return resolved;
        }
      } catch (_) {
        // Fall back to hostname/default when platform channel is unavailable.
      }
      return isUsableDeviceName(hostname) ? hostname : 'Android';
    }

    if (_isIos) {
      try {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        if (isUsableDeviceName(iosInfo.name)) {
          return iosInfo.name.trim();
        }
        if (isUsableDeviceName(iosInfo.model)) {
          return iosInfo.model.trim();
        }
      } catch (_) {
        // Fall back to hostname/default when platform channel is unavailable.
      }
      return isUsableDeviceName(hostname) ? hostname : 'iPhone';
    }

    if (isUsableDeviceName(hostname)) {
      return hostname;
    }

    try {
      if (_isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        if (isUsableDeviceName(windowsInfo.computerName)) {
          return windowsInfo.computerName.trim();
        }
      } else if (_isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        if (isUsableDeviceName(linuxInfo.prettyName)) {
          return linuxInfo.prettyName.trim();
        }
      } else if (_isMacOs) {
        final macOsInfo = await _deviceInfoPlugin.macOsInfo;
        if (isUsableDeviceName(macOsInfo.computerName)) {
          return macOsInfo.computerName.trim();
        }
      }
    } catch (_) {
      // Fall back to default when platform channel is unavailable.
    }

    return hostname.isNotEmpty ? hostname : 'Landa';
  }

  static String? _resolveAndroidName({
    required String deviceName,
    required String manufacturer,
    required String model,
    required String brand,
  }) {
    final trimmedDeviceName = deviceName.trim();
    if (isUsableDeviceName(trimmedDeviceName)) {
      return trimmedDeviceName;
    }

    final trimmedManufacturer = manufacturer.trim();
    final trimmedModel = model.trim();
    if (isUsableDeviceName(trimmedModel)) {
      if (isUsableDeviceName(trimmedManufacturer) &&
          !trimmedModel.toLowerCase().startsWith(
            trimmedManufacturer.toLowerCase(),
          )) {
        return '$trimmedManufacturer $trimmedModel';
      }
      return trimmedModel;
    }

    final trimmedBrand = brand.trim();
    if (isUsableDeviceName(trimmedBrand)) {
      return trimmedBrand;
    }

    return null;
  }

  static bool isUsableDeviceName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return false;
    }
    final lower = trimmed.toLowerCase();
    return lower != 'localhost' &&
        lower != 'localhost.localdomain' &&
        lower != '127.0.0.1' &&
        lower != '::1' &&
        lower != 'unknown';
  }
}
