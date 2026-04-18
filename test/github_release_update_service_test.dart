import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/github_release_update_service.dart';

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
                'assets': [],
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
    },
  );
}
