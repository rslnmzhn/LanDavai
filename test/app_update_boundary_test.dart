import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/application/app_update_boundary.dart';
import 'package:landa/app/update/domain/app_update_models.dart';

void main() {
  AppUpdateBoundary createBoundary({
    required Future<String> Function() currentVersionLoader,
    required Future<AppUpdateRelease> Function() latestReleaseLoader,
    Future<AppUpdateTarget> Function()? targetResolver,
    AppUpdateAsset Function({
      required AppUpdateRelease release,
      required AppUpdateTarget target,
    })?
    assetSelector,
    Future<File> Function(AppUpdateAsset asset)? assetDownloader,
    Future<File> Function(
      AppUpdateAsset asset, {
      AppUpdateDownloadProgressCallback? onProgress,
    })?
    assetDownloaderWithProgress,
    Future<void> Function({required AppUpdateAsset asset, required File file})?
    downloadedAssetInstaller,
  }) {
    return AppUpdateBoundary(
      currentVersionLoader: currentVersionLoader,
      latestReleaseLoader: latestReleaseLoader,
      targetResolver:
          targetResolver ??
          () async => const AppUpdateTarget(
            platform: AppUpdateRuntimePlatform.windows,
            archPreferences: <String>['x86_64'],
          ),
      assetSelector:
          assetSelector ??
          ({
            required AppUpdateRelease release,
            required AppUpdateTarget target,
          }) {
            return release.assets.first;
          },
      assetDownloader:
          assetDownloader ??
          (assetDownloaderWithProgress == null
              ? (asset) async => File('C:/temp/${asset.fileName}')
              : null),
      assetDownloaderWithProgress: assetDownloaderWithProgress,
      downloadedAssetInstaller:
          downloadedAssetInstaller ?? ({required asset, required file}) async {},
    );
  }

  AppUpdateRelease releaseWithAsset(String version) {
    return AppUpdateRelease(
      version: version,
      tag: 'v$version',
      releasePageUrl:
          'https://github.com/rslnmzhn/LanDavai/releases/tag/v$version',
      assets: const <AppUpdateAsset>[
        AppUpdateAsset(
          platform: 'windows',
          arch: 'x86_64',
          format: 'zip',
          primary: true,
          fileName: 'landa.zip',
          size: 100,
          sha256: 'hash',
          downloadUrl: 'https://example.com/landa.zip',
        ),
      ],
    );
  }

  AppUpdateRelease androidReleaseWithAsset(String version) {
    return AppUpdateRelease(
      version: version,
      tag: 'v$version',
      releasePageUrl:
          'https://github.com/rslnmzhn/LanDavai/releases/tag/v$version',
      assets: const <AppUpdateAsset>[
        AppUpdateAsset(
          platform: 'android',
          arch: 'arm64-v8a',
          format: 'apk',
          primary: true,
          fileName: 'landa-v1.1.0-android-arm64-v8a.apk',
          size: 100,
          sha256: 'hash',
          downloadUrl: 'https://example.com/landa-v1.1.0-android-arm64-v8a.apk',
        ),
      ],
    );
  }

  test(
    'marks the installed version as up to date when releases match',
    () async {
      final boundary = createBoundary(
        currentVersionLoader: () async => '1.2.3',
        latestReleaseLoader: () async => releaseWithAsset('1.2.3'),
      );

      await boundary.initialize();
      await boundary.checkForUpdates();

      expect(boundary.currentVersion, '1.2.3');
      expect(boundary.phase, AppUpdateCheckPhase.upToDate);
      expect(boundary.isUpdateAvailable, isFalse);
    },
  );

  test(
    'marks an update as available when GitHub has a newer stable release',
    () async {
      final boundary = createBoundary(
        currentVersionLoader: () async => '1.2.3',
        latestReleaseLoader: () async => releaseWithAsset('1.3.0'),
      );

      await boundary.initialize();
      await boundary.checkForUpdates();

      expect(boundary.phase, AppUpdateCheckPhase.updateAvailable);
      expect(boundary.latestRelease?.version, '1.3.0');
      expect(boundary.selectedAsset?.fileName, 'landa.zip');
    },
  );

  test('treats older or equal GitHub releases as no-update path', () async {
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.3.0',
      latestReleaseLoader: () async => releaseWithAsset('1.2.9'),
    );

    await boundary.initialize();
    await boundary.checkForUpdates();

    expect(boundary.phase, AppUpdateCheckPhase.upToDate);
  });

  test('fails gracefully when the GitHub lookup throws', () async {
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.2.3',
      latestReleaseLoader: () async {
        throw Exception('network unavailable');
      },
    );

    await boundary.initialize();
    await boundary.checkForUpdates();

    expect(boundary.phase, AppUpdateCheckPhase.failed);
    expect(boundary.lastError, contains('network unavailable'));
    expect(boundary.currentVersion, '1.2.3');
  });

  test('applyUpdate downloads desktop asset without opening it', () async {
    final applied = <String>[];
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => releaseWithAsset('1.1.0'),
      assetDownloader: (asset) async => File('C:/temp/${asset.fileName}'),
      downloadedAssetInstaller: ({required asset, required file}) async {
        applied.add('${asset.fileName}:${file.path}');
      },
    );

    await boundary.initialize();
    await boundary.checkForUpdates();
    await boundary.applyUpdate();

    expect(boundary.applyPhase, AppUpdateApplyPhase.readyToInstall);
    expect(boundary.downloadedAssetPath, 'C:/temp/landa.zip');
    expect(boundary.canInstallDownloadedUpdate, isTrue);
    expect(applied, isEmpty);
  });

  test('installDownloadedUpdate opens an existing desktop asset', () async {
    final temp = await Directory.systemTemp.createTemp('landa_update_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final file = File('${temp.path}/landa.zip');
    final applied = <String>[];
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => releaseWithAsset('1.1.0'),
      assetDownloader: (asset) async {
        await file.writeAsString('zip');
        return file;
      },
      downloadedAssetInstaller: ({required asset, required file}) async {
        applied.add('${asset.fileName}:${file.path}');
      },
    );

    await boundary.initialize();
    await boundary.checkForUpdates();
    await boundary.applyUpdate();
    await boundary.installDownloadedUpdate();

    expect(boundary.applyPhase, AppUpdateApplyPhase.readyToInstall);
    expect(applied, <String>['landa.zip:${file.path}']);
  });

  test('installDownloadedUpdate resets when downloaded file is missing', () async {
    final temp = await Directory.systemTemp.createTemp('landa_update_missing_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final file = File('${temp.path}/landa.zip');
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => releaseWithAsset('1.1.0'),
      assetDownloader: (asset) async {
        await file.writeAsString('zip');
        return file;
      },
    );

    await boundary.initialize();
    await boundary.checkForUpdates();
    await boundary.applyUpdate();
    await file.delete();
    await boundary.installDownloadedUpdate();

    expect(boundary.applyPhase, AppUpdateApplyPhase.idle);
    expect(boundary.applyMessage, AppUpdateBoundary.fileNotFoundMessage);
    expect(boundary.downloadedAssetPath, isNull);
    expect(boundary.canInstallDownloadedUpdate, isFalse);
    expect(boundary.isUpdateAvailable, isTrue);
  });

  test('applyUpdate fails gracefully when the download step throws', () async {
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => releaseWithAsset('1.1.0'),
      assetDownloader: (asset) async {
        throw Exception('download failed');
      },
    );

    await boundary.initialize();
    await boundary.checkForUpdates();
    await boundary.applyUpdate();

    expect(boundary.applyPhase, AppUpdateApplyPhase.failed);
    expect(boundary.applyMessage, contains('download failed'));
    expect(boundary.canInstallDownloadedUpdate, isFalse);
  });

  test('applyUpdate tracks download progress and resets after completion', () async {
    final observedProgress = <double?>[];
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => releaseWithAsset('1.1.0'),
      assetDownloaderWithProgress: (asset, {onProgress}) async {
        onProgress?.call(0, 100);
        onProgress?.call(50, 100);
        onProgress?.call(100, 100);
        return File('C:/temp/${asset.fileName}');
      },
    );
    boundary.addListener(() {
      if (boundary.isDownloading) {
        observedProgress.add(boundary.downloadProgress);
      }
    });

    await boundary.initialize();
    await boundary.checkForUpdates();
    await boundary.applyUpdate();

    expect(observedProgress, containsAllInOrder(<double?>[0.0, 0.5, 1.0]));
    expect(boundary.isApplying, isFalse);
    expect(boundary.downloadProgress, isNull);
    expect(boundary.applyPhase, AppUpdateApplyPhase.readyToInstall);
  });

  test(
    'Android APK install failure preserves downloaded file for retry without re-downloading',
    () async {
      final temp = await Directory.systemTemp.createTemp('landa_android_retry_');
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final apkFile = File('${temp.path}/landa-v1.1.0-android-arm64-v8a.apk');
      var downloadCalls = 0;
      var installCalls = 0;
      final boundary = createBoundary(
        currentVersionLoader: () async => '1.0.0',
        latestReleaseLoader: () async => androidReleaseWithAsset('1.1.0'),
        targetResolver: () async => const AppUpdateTarget(
          platform: AppUpdateRuntimePlatform.android,
          archPreferences: <String>['arm64-v8a'],
        ),
        assetDownloader: (asset) async {
          downloadCalls += 1;
          await apkFile.writeAsString('apk');
          return apkFile;
        },
        downloadedAssetInstaller: ({required asset, required file}) async {
          installCalls += 1;
          if (installCalls == 1) {
            throw StateError(
              'Allow Landa to install unknown apps, then tap install again.',
            );
          }
        },
      );

      await boundary.initialize();
      await boundary.checkForUpdates();
      await boundary.applyUpdate();

      expect(downloadCalls, 1);
      expect(installCalls, 1);
      expect(boundary.applyPhase, AppUpdateApplyPhase.failed);
      expect(
        boundary.applyMessage,
        'Allow Landa to install unknown apps, then tap install again.',
      );
      expect(boundary.downloadedAssetPath, apkFile.path);
      expect(boundary.canInstallDownloadedUpdate, isTrue);

      await boundary.installDownloadedUpdate();

      expect(downloadCalls, 1);
      expect(installCalls, 2);
      expect(boundary.applyPhase, AppUpdateApplyPhase.readyToInstall);
      expect(boundary.canInstallDownloadedUpdate, isTrue);
    },
  );

  test(
    'desktop install failure keeps downloaded file ready for retry without re-downloading',
    () async {
      final temp = await Directory.systemTemp.createTemp('landa_desktop_retry_');
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final zipFile = File('${temp.path}/landa.zip');
      var downloadCalls = 0;
      var installCalls = 0;
      final boundary = createBoundary(
        currentVersionLoader: () async => '1.0.0',
        latestReleaseLoader: () async => releaseWithAsset('1.1.0'),
        assetDownloader: (asset) async {
          downloadCalls += 1;
          await zipFile.writeAsString('zip');
          return zipFile;
        },
        downloadedAssetInstaller: ({required asset, required file}) async {
          installCalls += 1;
          if (installCalls == 1) {
            throw StateError('Opener failed');
          }
        },
      );

      await boundary.initialize();
      await boundary.checkForUpdates();
      await boundary.applyUpdate();
      await boundary.installDownloadedUpdate();

      expect(downloadCalls, 1);
      expect(installCalls, 1);
      expect(boundary.applyPhase, AppUpdateApplyPhase.failed);
      expect(boundary.applyMessage, 'Opener failed');
      expect(boundary.canInstallDownloadedUpdate, isTrue);

      await boundary.installDownloadedUpdate();

      expect(downloadCalls, 1);
      expect(installCalls, 2);
      expect(boundary.applyPhase, AppUpdateApplyPhase.readyToInstall);
    },
  );
}
