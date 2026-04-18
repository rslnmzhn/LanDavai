import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/application/app_update_boundary.dart';
import 'package:landa/app/update/domain/app_update_models.dart';

void main() {
  test(
    'marks the installed version as up to date when releases match',
    () async {
      final boundary = AppUpdateBoundary(
        currentVersionLoader: () async => '1.2.3',
        latestReleaseLoader: () async => const AppUpdateRelease(
          version: '1.2.3',
          tag: 'v1.2.3',
          releasePageUrl:
              'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.2.3',
        ),
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
      final boundary = AppUpdateBoundary(
        currentVersionLoader: () async => '1.2.3',
        latestReleaseLoader: () async => const AppUpdateRelease(
          version: '1.3.0',
          tag: 'v1.3.0',
          releasePageUrl:
              'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.3.0',
        ),
      );

      await boundary.initialize();
      await boundary.checkForUpdates();

      expect(boundary.phase, AppUpdateCheckPhase.updateAvailable);
      expect(boundary.latestRelease?.version, '1.3.0');
    },
  );

  test('treats older or equal GitHub releases as no-update path', () async {
    final boundary = AppUpdateBoundary(
      currentVersionLoader: () async => '1.3.0',
      latestReleaseLoader: () async => const AppUpdateRelease(
        version: '1.2.9',
        tag: 'v1.2.9',
        releasePageUrl:
            'https://github.com/rslnmzhn/LanDavai/releases/tag/v1.2.9',
      ),
    );

    await boundary.initialize();
    await boundary.checkForUpdates();

    expect(boundary.phase, AppUpdateCheckPhase.upToDate);
  });

  test('fails gracefully when the GitHub lookup throws', () async {
    final boundary = AppUpdateBoundary(
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
}
