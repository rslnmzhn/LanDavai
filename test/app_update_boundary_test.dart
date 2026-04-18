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
    Future<void> Function({required AppUpdateAsset asset, required File file})?
    downloadedAssetOpener,
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
          assetDownloader ?? (asset) async => File('C:/temp/${asset.fileName}'),
      downloadedAssetOpener:
          downloadedAssetOpener ?? ({required asset, required file}) async {},
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

  test('applyUpdate downloads and opens the selected asset', () async {
    final applied = <String>[];
    final boundary = createBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => releaseWithAsset('1.1.0'),
      assetDownloader: (asset) async => File('C:/temp/${asset.fileName}'),
      downloadedAssetOpener: ({required asset, required file}) async {
        applied.add('${asset.fileName}:${file.path}');
      },
    );

    await boundary.initialize();
    await boundary.checkForUpdates();
    await boundary.applyUpdate();

    expect(boundary.applyPhase, AppUpdateApplyPhase.readyToInstall);
    expect(applied, <String>['landa.zip:C:/temp/landa.zip']);
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
  });
}
