import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/utils/local_device_name_resolver.dart';

void main() {
  group('LocalDeviceNameResolver', () {
    test('uses Android device name when available and not localhost', () async {
      final resolver = LocalDeviceNameResolver(
        deviceInfoPlugin: _FakeDeviceInfoPlugin(
          android: _androidInfo(
            name: 'Pixel 8 Pro',
            manufacturer: 'Google',
            model: 'Pixel 8 Pro',
            brand: 'google',
          ),
        ),
        localHostnameProvider: () => 'localhost',
        isAndroidOverride: true,
        isIosOverride: false,
      );

      expect(await resolver.resolve(), 'Pixel 8 Pro');
    });

    test(
      'falls back to manufacturer and model on Android when name is localhost',
      () async {
        final resolver = LocalDeviceNameResolver(
          deviceInfoPlugin: _FakeDeviceInfoPlugin(
            android: _androidInfo(
              name: 'localhost',
              manufacturer: 'Samsung',
              model: 'SM-S918B',
              brand: 'samsung',
            ),
          ),
          localHostnameProvider: () => 'localhost',
          isAndroidOverride: true,
          isIosOverride: false,
        );

        expect(await resolver.resolve(), 'Samsung SM-S918B');
      },
    );

    test(
      'does not duplicate manufacturer when Android model already includes it',
      () async {
        final resolver = LocalDeviceNameResolver(
          deviceInfoPlugin: _FakeDeviceInfoPlugin(
            android: _androidInfo(
              name: '',
              manufacturer: 'Google',
              model: 'Google Pixel 7',
              brand: 'google',
            ),
          ),
          localHostnameProvider: () => 'localhost',
          isAndroidOverride: true,
          isIosOverride: false,
        );

        expect(await resolver.resolve(), 'Google Pixel 7');
      },
    );

    test('falls back to Android when device_info_plus throws', () async {
      final resolver = LocalDeviceNameResolver(
        deviceInfoPlugin: _ThrowingDeviceInfoPlugin(),
        localHostnameProvider: () => 'localhost',
        isAndroidOverride: true,
        isIosOverride: false,
      );

      expect(await resolver.resolve(), 'Android');
    });

    test('uses iOS device name when available', () async {
      final resolver = LocalDeviceNameResolver(
        deviceInfoPlugin: _FakeDeviceInfoPlugin(
          ios: _iosInfo(name: 'Ruslan iPhone', model: 'iPhone'),
        ),
        localHostnameProvider: () => 'localhost',
        isAndroidOverride: false,
        isIosOverride: true,
      );

      expect(await resolver.resolve(), 'Ruslan iPhone');
    });

    test('uses localHostname directly on desktop when usable', () async {
      final resolver = LocalDeviceNameResolver(
        deviceInfoPlugin: _ThrowingDeviceInfoPlugin(),
        localHostnameProvider: () => 'WORKSTATION-01',
        isAndroidOverride: false,
        isIosOverride: false,
        isWindowsOverride: true,
      );

      expect(await resolver.resolve(), 'WORKSTATION-01');
    });
  });
}

class _FakeDeviceInfoPlugin extends DeviceInfoPlugin {
  _FakeDeviceInfoPlugin({AndroidDeviceInfo? android, IosDeviceInfo? ios})
    : _android = android,
      _ios = ios;

  final AndroidDeviceInfo? _android;
  final IosDeviceInfo? _ios;

  @override
  Future<AndroidDeviceInfo> get androidInfo async => _android!;

  @override
  Future<IosDeviceInfo> get iosInfo async => _ios!;
}

class _ThrowingDeviceInfoPlugin extends DeviceInfoPlugin {
  @override
  Future<AndroidDeviceInfo> get androidInfo async =>
      throw StateError('unavailable');

  @override
  Future<IosDeviceInfo> get iosInfo async => throw StateError('unavailable');
}

AndroidDeviceInfo _androidInfo({
  required String name,
  required String manufacturer,
  required String model,
  required String brand,
}) {
  return AndroidDeviceInfo.fromMap(<String, dynamic>{
    'version': <String, dynamic>{
      'baseOS': '',
      'codename': 'REL',
      'incremental': '1',
      'previewSdkInt': 0,
      'release': '14',
      'sdkInt': 34,
      'securityPatch': '2026-01-01',
    },
    'board': 'board',
    'bootloader': 'bootloader',
    'brand': brand,
    'device': 'device',
    'display': 'display',
    'fingerprint': 'fingerprint',
    'hardware': 'hardware',
    'host': 'host',
    'id': 'id',
    'manufacturer': manufacturer,
    'model': model,
    'product': 'product',
    'name': name,
    'supported32BitAbis': <String>[],
    'supported64BitAbis': <String>['arm64-v8a'],
    'supportedAbis': <String>['arm64-v8a'],
    'tags': 'release-keys',
    'type': 'user',
    'isPhysicalDevice': true,
    'freeDiskSize': 1000,
    'totalDiskSize': 2000,
    'systemFeatures': <String>[],
    'serialNumber': 'unknown',
    'isLowRamDevice': false,
    'physicalRamSize': 8192,
    'availableRamSize': 4096,
  });
}

IosDeviceInfo _iosInfo({required String name, required String model}) {
  return IosDeviceInfo.fromMap(<String, dynamic>{
    'name': name,
    'systemName': 'iOS',
    'systemVersion': '18.0',
    'model': model,
    'modelName': model,
    'localizedModel': model,
    'identifierForVendor': 'vendor-id',
    'isPhysicalDevice': true,
    'isiOSAppOnMac': false,
    'freeDiskSize': 1000,
    'totalDiskSize': 2000,
    'physicalRamSize': 8192,
    'availableRamSize': 4096,
    'utsname': <String, dynamic>{
      'sysname': 'Darwin',
      'nodename': 'localhost',
      'release': '24.0.0',
      'version': 'Darwin Kernel',
      'machine': 'iPhone16,1',
    },
  });
}
