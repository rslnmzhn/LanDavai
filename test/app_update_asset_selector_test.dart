import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/app_update_asset_selector.dart';
import 'package:landa/app/update/domain/app_update_models.dart';

void main() {
  const selector = AppUpdateAssetSelector();

  const release = AppUpdateRelease(
    version: '1.2.0',
    tag: 'v1.2.0',
    releasePageUrl: 'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.2.0',
    assets: <AppUpdateAsset>[
      AppUpdateAsset(
        platform: 'android',
        arch: 'armeabi-v7a',
        format: 'apk',
        primary: true,
        fileName: 'landa-android-armeabi-v7a.apk',
        size: 1,
        sha256: 'a',
        downloadUrl: 'https://example.com/landa-android-armeabi-v7a.apk',
      ),
      AppUpdateAsset(
        platform: 'android',
        arch: 'arm64-v8a',
        format: 'apk',
        primary: true,
        fileName: 'landa-android-arm64-v8a.apk',
        size: 1,
        sha256: 'b',
        downloadUrl: 'https://example.com/landa-android-arm64-v8a.apk',
      ),
      AppUpdateAsset(
        platform: 'windows',
        arch: 'x86_64',
        format: 'zip',
        primary: true,
        fileName: 'windows.zip',
        size: 1,
        sha256: 'c',
        downloadUrl: 'https://example.com/windows.zip',
      ),
    ],
  );

  test('selects the correct Android ABI-specific APK', () {
    final asset = selector.selectAsset(
      release: release,
      target: const AppUpdateTarget(
        platform: AppUpdateRuntimePlatform.android,
        archPreferences: <String>['arm64-v8a', 'armeabi-v7a'],
      ),
    );

    expect(asset.fileName, 'landa-android-arm64-v8a.apk');
  });

  test('does not fall back to another Android ABI when exact ABI is absent', () {
    expect(
      () => selector.selectAsset(
        release: release,
        target: const AppUpdateTarget(
          platform: AppUpdateRuntimePlatform.android,
          archPreferences: <String>['x86_64'],
        ),
      ),
      throwsStateError,
    );
  });

  test('selects the correct desktop asset for Windows', () {
    final asset = selector.selectAsset(
      release: release,
      target: const AppUpdateTarget(
        platform: AppUpdateRuntimePlatform.windows,
        archPreferences: <String>['x86_64'],
      ),
    );

    expect(asset.fileName, 'windows.zip');
  });
}
