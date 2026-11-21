import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/application/app_update_boundary.dart';
import 'package:landa/app/update/domain/app_update_models.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/settings/presentation/app_settings_tab_sections.dart';
import 'package:path/path.dart' as p;

import 'test_support/localized_test_app.dart';

void main() {
  testWidgets('settings network tab shows the update-available surface', (
    tester,
  ) async {
    final appUpdateBoundary = AppUpdateBoundary(
      currentVersionLoader: () async => '1.0.0',
      latestReleaseLoader: () async => const AppUpdateRelease(
        version: '1.1.0',
        tag: 'v1.1.0',
        releasePageUrl:
            'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.1.0',
        assets: <AppUpdateAsset>[
          AppUpdateAsset(
            platform: 'windows',
            arch: 'x86_64',
            format: 'zip',
            primary: true,
            fileName: 'landa-v1.1.0-windows-x64.zip',
            size: 10,
            sha256: 'hash',
            downloadUrl: 'https://example.com/landa-v1.1.0-windows-x64.zip',
          ),
        ],
      ),
      targetResolver: () async => const AppUpdateTarget(
        platform: AppUpdateRuntimePlatform.windows,
        archPreferences: <String>['x86_64'],
      ),
      assetSelector: ({required release, required target}) =>
          release.assets.first,
      assetDownloader: (asset) async => throw UnimplementedError(),
      downloadedAssetInstaller: ({required asset, required file}) async {},
    );
    await appUpdateBoundary.initialize();
    await appUpdateBoundary.checkForUpdates();

    await _pumpNetworkTab(
      tester,
      appUpdateBoundary: appUpdateBoundary,
      locale: const Locale('en'),
    );

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Current version: 1.0.0'), findsOneWidget);
    expect(find.text('Latest release: 1.1.0'), findsOneWidget);
    expect(find.text('Update available: 1.1.0'), findsOneWidget);
    expect(
      find.text('Update asset: landa-v1.1.0-windows-x64.zip'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Check for updates'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Download update'),
      findsOneWidget,
    );
  });

  testWidgets(
    'tapping Download update in Russian shows progress and transitions to Install update',
    (tester) async {
      late Directory tempDir;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('landa_ui_update_');
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final downloadedFile = File(
        p.join(tempDir.path, 'landa-v1.1.0-linux-x86_64.AppImage'),
      );
      final downloadCompleter = Completer<File>();
      AppUpdateDownloadProgressCallback? capturedProgress;
      final installedPaths = <String>[];

      final appUpdateBoundary = AppUpdateBoundary(
        currentVersionLoader: () async => '1.0.0',
        latestReleaseLoader: () async => const AppUpdateRelease(
          version: '1.1.0',
          tag: 'v1.1.0',
          releasePageUrl:
              'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.1.0',
          assets: <AppUpdateAsset>[
            AppUpdateAsset(
              platform: 'linux',
              arch: 'x86_64',
              format: 'appimage',
              primary: true,
              fileName: 'landa-v1.1.0-linux-x86_64.AppImage',
              size: 2048,
              sha256: 'hash',
              downloadUrl:
                  'https://example.com/landa-v1.1.0-linux-x86_64.AppImage',
            ),
          ],
        ),
        targetResolver: () async => const AppUpdateTarget(
          platform: AppUpdateRuntimePlatform.linux,
          archPreferences: <String>['x86_64'],
        ),
        assetSelector: ({required release, required target}) =>
            release.assets.first,
        assetDownloaderWithProgress: (asset, {onProgress}) {
          capturedProgress = onProgress;
          return downloadCompleter.future;
        },
        downloadedAssetInstaller: ({required asset, required file}) async {
          installedPaths.add(file.path);
        },
      );
      await appUpdateBoundary.initialize();
      await appUpdateBoundary.checkForUpdates();

      await _pumpNetworkTab(
        tester,
        appUpdateBoundary: appUpdateBoundary,
        locale: const Locale('ru'),
      );

      final downloadButton = find.widgetWithText(
        OutlinedButton,
        'Скачать обновление',
      );
      expect(downloadButton, findsOneWidget);
      await tester.ensureVisible(downloadButton);
      await tester.tap(downloadButton);
      await tester.pump();

      expect(find.text('Скачиваем обновление...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      capturedProgress?.call(1024, 2048);
      await tester.pump();
      expect(find.textContaining('50%'), findsOneWidget);

      await tester.runAsync(() async {
        downloadedFile.writeAsStringSync('appimage');
      });
      downloadCompleter.complete(downloadedFile);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Файл обновления готов: ${downloadedFile.path}'),
        findsOneWidget,
      );
      final installButton = find.widgetWithText(
        OutlinedButton,
        'Установить обновление',
      );
      expect(installButton, findsOneWidget);

      await tester.ensureVisible(installButton);
      await tester.tap(installButton);
      await _waitForApplyIdle(tester, appUpdateBoundary);

      expect(installedPaths, <String>[downloadedFile.path]);
    },
  );

  testWidgets(
    'download failure shows error details and Retry download succeeds on tap',
    (tester) async {
      late Directory tempDir;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('landa_ui_retry_');
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final downloadedFile = File(
        p.join(tempDir.path, 'landa-v1.1.0-windows-x64.zip'),
      );
      var attempts = 0;

      final appUpdateBoundary = AppUpdateBoundary(
        currentVersionLoader: () async => '1.0.0',
        latestReleaseLoader: () async => const AppUpdateRelease(
          version: '1.1.0',
          tag: 'v1.1.0',
          releasePageUrl:
              'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.1.0',
          assets: <AppUpdateAsset>[
            AppUpdateAsset(
              platform: 'windows',
              arch: 'x86_64',
              format: 'zip',
              primary: true,
              fileName: 'landa-v1.1.0-windows-x64.zip',
              size: 1024,
              sha256: 'hash',
              downloadUrl: 'https://example.com/landa-v1.1.0-windows-x64.zip',
            ),
          ],
        ),
        targetResolver: () async => const AppUpdateTarget(
          platform: AppUpdateRuntimePlatform.windows,
          archPreferences: <String>['x86_64'],
        ),
        assetSelector: ({required release, required target}) =>
            release.assets.first,
        assetDownloader: (asset) async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('Asset download failed with status 503');
          }
          downloadedFile.writeAsStringSync('zip');
          return downloadedFile;
        },
        downloadedAssetInstaller: ({required asset, required file}) async {},
      );
      await appUpdateBoundary.initialize();
      await appUpdateBoundary.checkForUpdates();

      await _pumpNetworkTab(
        tester,
        appUpdateBoundary: appUpdateBoundary,
        locale: const Locale('en'),
      );

      final downloadButton = find.widgetWithText(
        OutlinedButton,
        'Download update',
      );
      await tester.ensureVisible(downloadButton);
      await tester.tap(downloadButton);
      await tester.pump();

      expect(find.text('Unable to apply the update right now.'), findsOneWidget);
      expect(
        find.text('Asset download failed with status 503'),
        findsOneWidget,
      );
      final retryButton = find.widgetWithText(OutlinedButton, 'Retry download');
      expect(retryButton, findsOneWidget);

      await tester.ensureVisible(retryButton);
      await tester.tap(retryButton);
      await _waitForApplyIdle(tester, appUpdateBoundary);

      expect(attempts, 2);
      expect(
        find.text('Update file is ready: ${downloadedFile.path}'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Install update'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Android APK permission error shows actionable message and Install update retries without re-downloading',
    (tester) async {
      late Directory tempDir;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('landa_ui_android_');
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final apkFile = File(
        p.join(tempDir.path, 'landa-v1.1.0-android-arm64-v8a.apk'),
      );
      var downloadCalls = 0;
      var installCalls = 0;

      final appUpdateBoundary = AppUpdateBoundary(
        currentVersionLoader: () async => '1.0.0',
        latestReleaseLoader: () async => const AppUpdateRelease(
          version: '1.1.0',
          tag: 'v1.1.0',
          releasePageUrl:
              'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.1.0',
          assets: <AppUpdateAsset>[
            AppUpdateAsset(
              platform: 'android',
              arch: 'arm64-v8a',
              format: 'apk',
              primary: true,
              fileName: 'landa-v1.1.0-android-arm64-v8a.apk',
              size: 1024,
              sha256: 'hash',
              downloadUrl:
                  'https://example.com/landa-v1.1.0-android-arm64-v8a.apk',
            ),
          ],
        ),
        targetResolver: () async => const AppUpdateTarget(
          platform: AppUpdateRuntimePlatform.android,
          archPreferences: <String>['arm64-v8a'],
        ),
        assetSelector: ({required release, required target}) =>
            release.assets.first,
        assetDownloader: (asset) async {
          downloadCalls += 1;
          apkFile.writeAsStringSync('apk');
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
      await appUpdateBoundary.initialize();
      await appUpdateBoundary.checkForUpdates();

      await _pumpNetworkTab(
        tester,
        appUpdateBoundary: appUpdateBoundary,
        locale: const Locale('en'),
      );

      final downloadAndInstallButton = find.widgetWithText(
        OutlinedButton,
        'Download and install',
      );
      await tester.ensureVisible(downloadAndInstallButton);
      await tester.tap(downloadAndInstallButton);
      await _waitForApplyIdle(tester, appUpdateBoundary);

      expect(downloadCalls, 1);
      expect(installCalls, 1);
      expect(
        find.text(
          'Allow Landa to install unknown apps, then tap install again.',
        ),
        findsOneWidget,
      );
      final installButton = find.widgetWithText(
        OutlinedButton,
        'Install update',
      );
      expect(installButton, findsOneWidget);

      await tester.ensureVisible(installButton);
      await tester.tap(installButton);
      await _waitForApplyIdle(tester, appUpdateBoundary);

      expect(downloadCalls, 1);
      expect(installCalls, 2);
      expect(
        find.text('Update file is ready: ${apkFile.path}'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpNetworkTab(
  WidgetTester tester, {
  required AppUpdateBoundary appUpdateBoundary,
  required Locale locale,
}) async {
  final targetController = TextEditingController();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    targetController.dispose();
  });
  await tester.pumpWidget(
    buildLocalizedTestApp(
      locale: locale,
      home: Scaffold(
        body: AppSettingsNetworkTab(
          settings: AppSettings.defaults,
          appUpdateBoundary: appUpdateBoundary,
          configuredDiscoveryTargets: const <String>[],
          configuredTargetController: targetController,
          onAddConfiguredTarget: () async {},
          onRemoveConfiguredTarget: (_) async {},
          onBackgroundIntervalChanged: (_) {},
          onDownloadAttemptNotificationsChanged: (_) {},
        ),
      ),
    ),
  );
  for (var i = 0; i < 50 && find.byType(Scrollable).evaluate().isEmpty; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();

  expect(find.byType(Scrollable), findsAtLeastNWidgets(1));
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
  await tester.pumpAndSettle();
}

Future<void> _waitForApplyIdle(
  WidgetTester tester,
  AppUpdateBoundary boundary,
) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100 && boundary.isApplying; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pump();
  await tester.pump();
}
