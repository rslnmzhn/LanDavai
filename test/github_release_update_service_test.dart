import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/app_update_asset_selector.dart';
import 'package:landa/app/update/data/github_release_update_service.dart';
import 'package:landa/app/update/domain/app_update_models.dart';

void main() {
  test(
    'loads the latest stable release through the GitHub manifest contract',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final version = '1.2.3';
      final tag = 'v1.2.3';
      final manifestName = 'landa-v$version-release-manifest.json';
      final releaseApiPath = '/repos/rslnmzhn/LanDavai/releases/latest';
      final manifestPath = '/$manifestName';

      server.listen((request) async {
        if (request.uri.path == releaseApiPath) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'tag_name': tag,
                'html_url':
                    'https://github.com/rslnmzhn/LanDavai/releases/tag/$tag',
                'draft': false,
                'prerelease': false,
                'assets': [
                  {
                    'name': manifestName,
                    'browser_download_url':
                        'http://127.0.0.1:${server.port}$manifestPath',
                  },
                ],
              }),
            );
          await request.response.close();
          return;
        }

        if (request.uri.path == manifestPath) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'schemaVersion': 1,
                'release': {
                  'channel': 'stable',
                  'tag': tag,
                  'version': version,
                  'draft': false,
                  'prerelease': false,
                },
                'assets': [
                  {
                    'platform': 'android',
                    'arch': 'arm64-v8a',
                    'format': 'apk',
                    'primary': true,
                    'fileName': 'landa-v1.2.3-android-arm64-v8a.apk',
                    'size': 123,
                    'sha256': 'abc',
                    'downloadUrl':
                        'https://github.com/rslnmzhn/LanDavai/releases/download/$tag/landa-v1.2.3-android-arm64-v8a.apk',
                  },
                ],
              }),
            );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final service = GithubReleaseUpdateService(
        owner: 'rslnmzhn',
        repository: 'LanDavai',
        latestReleaseUri: Uri.parse(
          'http://127.0.0.1:${server.port}$releaseApiPath',
        ),
      );

      final release = await service.fetchLatestStableRelease();

      expect(release.version, version);
      expect(release.tag, tag);
      expect(
        release.releasePageUrl,
        'https://github.com/rslnmzhn/LanDavai/releases/tag/$tag',
      );
      expect(release.assets, hasLength(1));
      expect(release.assets.single.platform, 'android');
      expect(release.assets.single.arch, 'arm64-v8a');
    },
  );

  test(
    'follows 302 manifest redirect and selects assets across full release contract',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      const version = '0.2.4';
      const tag = 'v0.2.4';
      const manifestName = 'landa-v$version-release-manifest.json';
      const releaseApiPath = '/repos/rslnmzhn/LanDavai/releases/latest';
      const manifestRedirectPath = '/releases/download/$tag/$manifestName';
      const manifestCdnPath = '/cdn/$manifestName';

      server.listen((request) async {
        if (request.uri.path == releaseApiPath) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'tag_name': tag,
                'html_url':
                    'https://github.com/rslnmzhn/LanDavai/releases/tag/$tag',
                'draft': false,
                'prerelease': false,
                'assets': [
                  {
                    'name': manifestName,
                    'browser_download_url':
                        'http://127.0.0.1:${server.port}$manifestRedirectPath',
                  },
                ],
              }),
            );
          await request.response.close();
          return;
        }

        if (request.uri.path == manifestRedirectPath) {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(
              HttpHeaders.locationHeader,
              'http://127.0.0.1:${server.port}$manifestCdnPath',
            );
          await request.response.close();
          return;
        }

        if (request.uri.path == manifestCdnPath) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'schemaVersion': 1,
                'release': {
                  'channel': 'stable',
                  'tag': tag,
                  'version': version,
                  'draft': false,
                  'prerelease': false,
                },
                'assets': [
                  {
                    'platform': 'android',
                    'arch': 'armeabi-v7a',
                    'format': 'apk',
                    'primary': true,
                    'fileName': 'landa-v$version-android-armeabi-v7a.apk',
                    'size': 100,
                    'sha256': 'a' * 64,
                    'downloadUrl':
                        'https://github.com/rslnmzhn/LanDavai/releases/download/$tag/landa-v$version-android-armeabi-v7a.apk',
                  },
                  {
                    'platform': 'android',
                    'arch': 'arm64-v8a',
                    'format': 'apk',
                    'primary': true,
                    'fileName': 'landa-v$version-android-arm64-v8a.apk',
                    'size': 200,
                    'sha256': 'b' * 64,
                    'downloadUrl':
                        'https://github.com/rslnmzhn/LanDavai/releases/download/$tag/landa-v$version-android-arm64-v8a.apk',
                  },
                  {
                    'platform': 'android',
                    'arch': 'x86_64',
                    'format': 'apk',
                    'primary': true,
                    'fileName': 'landa-v$version-android-x86_64.apk',
                    'size': 300,
                    'sha256': 'c' * 64,
                    'downloadUrl':
                        'https://github.com/rslnmzhn/LanDavai/releases/download/$tag/landa-v$version-android-x86_64.apk',
                  },
                  {
                    'platform': 'linux',
                    'arch': 'x86_64',
                    'format': 'appimage',
                    'primary': true,
                    'fileName': 'landa-v$version-linux-x86_64.AppImage',
                    'size': 400,
                    'sha256': 'd' * 64,
                    'downloadUrl':
                        'https://github.com/rslnmzhn/LanDavai/releases/download/$tag/landa-v$version-linux-x86_64.AppImage',
                  },
                  {
                    'platform': 'linux',
                    'arch': 'x86_64',
                    'format': 'zip',
                    'primary': false,
                    'fileName': 'landa-v$version-linux-x64.zip',
                    'size': 500,
                    'sha256': 'e' * 64,
                    'downloadUrl':
                        'https://github.com/rslnmzhn/LanDavai/releases/download/$tag/landa-v$version-linux-x64.zip',
                  },
                  {
                    'platform': 'windows',
                    'arch': 'x86_64',
                    'format': 'zip',
                    'primary': true,
                    'fileName': 'landa-v$version-windows-x64.zip',
                    'size': 600,
                    'sha256': 'f' * 64,
                    'downloadUrl':
                        'https://github.com/rslnmzhn/LanDavai/releases/download/$tag/landa-v$version-windows-x64.zip',
                  },
                ],
              }),
            );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final service = GithubReleaseUpdateService(
        owner: 'rslnmzhn',
        repository: 'LanDavai',
        latestReleaseUri: Uri.parse(
          'http://127.0.0.1:${server.port}$releaseApiPath',
        ),
      );

      final release = await service.fetchLatestStableRelease();
      const selector = AppUpdateAssetSelector();

      expect(release.assets, hasLength(6));
      expect(
        selector
            .selectAsset(
              release: release,
              target: const AppUpdateTarget(
                platform: AppUpdateRuntimePlatform.android,
                archPreferences: <String>['arm64-v8a', 'armeabi-v7a'],
              ),
            )
            .fileName,
        'landa-v$version-android-arm64-v8a.apk',
      );
      expect(
        selector
            .selectAsset(
              release: release,
              target: const AppUpdateTarget(
                platform: AppUpdateRuntimePlatform.linux,
                archPreferences: <String>['x86_64'],
              ),
            )
            .fileName,
        'landa-v$version-linux-x86_64.AppImage',
      );
      expect(
        selector
            .selectAsset(
              release: release,
              target: const AppUpdateTarget(
                platform: AppUpdateRuntimePlatform.windows,
                archPreferences: <String>['x86_64'],
              ),
            )
            .fileName,
        'landa-v$version-windows-x64.zip',
      );
    },
  );

  test('rejects non-HTTPS non-loopback asset downloadUrl in manifest', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    const version = '1.2.3';
    const tag = 'v1.2.3';
    const manifestName = 'landa-v$version-release-manifest.json';
    const releaseApiPath = '/repos/rslnmzhn/LanDavai/releases/latest';
    const manifestPath = '/$manifestName';

    server.listen((request) async {
      if (request.uri.path == releaseApiPath) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'tag_name': tag,
              'html_url':
                  'https://github.com/rslnmzhn/LanDavai/releases/tag/$tag',
              'draft': false,
              'prerelease': false,
              'assets': [
                {
                  'name': manifestName,
                  'browser_download_url':
                      'http://127.0.0.1:${server.port}$manifestPath',
                },
              ],
            }),
          );
        await request.response.close();
        return;
      }

      if (request.uri.path == manifestPath) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'schemaVersion': 1,
              'release': {
                'channel': 'stable',
                'tag': tag,
                'version': version,
                'draft': false,
                'prerelease': false,
              },
              'assets': [
                {
                  'platform': 'windows',
                  'arch': 'x86_64',
                  'format': 'zip',
                  'primary': true,
                  'fileName': 'landa-v1.2.3-windows-x64.zip',
                  'size': 123,
                  'sha256': 'abc',
                  'downloadUrl':
                      'http://example.com/landa-v1.2.3-windows-x64.zip',
                },
              ],
            }),
          );
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final service = GithubReleaseUpdateService(
      owner: 'rslnmzhn',
      repository: 'LanDavai',
      latestReleaseUri: Uri.parse(
        'http://127.0.0.1:${server.port}$releaseApiPath',
      ),
    );

    await expectLater(
      service.fetchLatestStableRelease,
      throwsA(isA<FormatException>()),
    );
  });
}
