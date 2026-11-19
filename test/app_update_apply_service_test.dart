import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/app_update_apply_service.dart';
import 'package:landa/app/update/domain/app_update_models.dart';
import 'package:landa/core/utils/path_opener.dart';

void main() {
  test(
    'Linux AppImage marks executable and opens containing folder',
    () async {
      final opener = _RecordingPathOpener();
      final commands = <(String, List<String>)>[];
      final service = AppUpdateApplyService(
        pathOpener: opener,
        isAndroidOverride: false,
        isLinuxOverride: true,
        processRunner: (executable, arguments) async {
          commands.add((executable, arguments));
          return ProcessResult(1, 0, '', '');
        },
      );
      const asset = AppUpdateAsset(
        platform: 'linux',
        arch: 'x86_64',
        format: 'appimage',
        primary: true,
        fileName: 'landa-v0.2.4-linux-x86_64.AppImage',
        size: 100,
        sha256: 'abc',
        downloadUrl: 'https://example.com/landa.AppImage',
      );
      final file = File('/tmp/landa-v0.2.4-linux-x86_64.AppImage');

      await service.openDownloadedAsset(asset: asset, file: file);

      expect(commands, hasLength(1));
      expect(commands.single.$1, 'chmod');
      expect(commands.single.$2, <String>['+x', file.path]);
      expect(opener.openedPaths, isEmpty);
      expect(opener.openedFolders, <String>[file.path]);
    },
  );

  test('Linux AppImage throws when chmod fails', () async {
    final opener = _RecordingPathOpener();
    final service = AppUpdateApplyService(
      pathOpener: opener,
      isAndroidOverride: false,
      isLinuxOverride: true,
      processRunner: (executable, arguments) async {
        return ProcessResult(1, 1, '', 'permission denied');
      },
    );
    const asset = AppUpdateAsset(
      platform: 'linux',
      arch: 'x86_64',
      format: 'appimage',
      primary: true,
      fileName: 'landa-v0.2.4-linux-x86_64.AppImage',
      size: 100,
      sha256: 'abc',
      downloadUrl: 'https://example.com/landa.AppImage',
    );

    await expectLater(
      () => service.openDownloadedAsset(
        asset: asset,
        file: File('/tmp/landa.AppImage'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('permission denied'),
        ),
      ),
    );
    expect(opener.openedFolders, isEmpty);
  });

  test(
    'desktop archive opens file path and falls back to containing folder on error',
    () async {
      final opener = _RecordingPathOpener(throwOnOpenPath: true);
      final service = AppUpdateApplyService(
        pathOpener: opener,
        isAndroidOverride: false,
        isLinuxOverride: false,
      );
      const asset = AppUpdateAsset(
        platform: 'windows',
        arch: 'x86_64',
        format: 'zip',
        primary: true,
        fileName: 'landa-v0.2.4-windows-x64.zip',
        size: 100,
        sha256: 'abc',
        downloadUrl: 'https://example.com/landa.zip',
      );
      final file = File('C:/Downloads/Landa/updates/landa.zip');

      await service.openDownloadedAsset(asset: asset, file: file);

      expect(opener.openedPaths, <String>[file.path]);
      expect(opener.openedFolders, <String>[file.path]);
    },
  );

  test(
    'Android APK invokes native installer and unwraps PlatformException message',
    () async {
      final opener = _RecordingPathOpener();
      final installedPaths = <String>[];
      final service = AppUpdateApplyService(
        pathOpener: opener,
        isAndroidOverride: true,
        isLinuxOverride: false,
        androidApkInstaller: (path) async {
          installedPaths.add(path);
          throw PlatformException(
            code: 'install_apk_failed',
            message: 'Allow Landa to install unknown apps, then tap install again.',
          );
        },
      );
      const asset = AppUpdateAsset(
        platform: 'android',
        arch: 'arm64-v8a',
        format: 'apk',
        primary: true,
        fileName: 'landa-v0.2.4-android-arm64-v8a.apk',
        size: 100,
        sha256: 'abc',
        downloadUrl: 'https://example.com/landa.apk',
      );
      final file = File('/data/user/0/com.example.landa/files/Landa/updates/landa.apk');

      await expectLater(
        () => service.openDownloadedAsset(asset: asset, file: file),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Allow Landa to install unknown apps, then tap install again.',
          ),
        ),
      );
      expect(installedPaths, <String>[file.path]);
      expect(opener.openedPaths, isEmpty);
      expect(opener.openedFolders, isEmpty);
    },
  );
}

class _RecordingPathOpener extends PathOpener {
  _RecordingPathOpener({this.throwOnOpenPath = false});

  final bool throwOnOpenPath;
  final List<String> openedPaths = <String>[];
  final List<String> openedFolders = <String>[];

  @override
  Future<void> openPath(String path) async {
    openedPaths.add(path);
    if (throwOnOpenPath) {
      throw StateError('No handler for $path');
    }
  }

  @override
  Future<void> openContainingFolder(String path) async {
    openedFolders.add(path);
  }
}
