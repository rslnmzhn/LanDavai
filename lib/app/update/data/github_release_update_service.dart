import 'dart:convert';
import 'dart:io';

import '../app_update_config.dart';
import '../domain/app_update_models.dart';

class GithubReleaseUpdateService {
  GithubReleaseUpdateService({
    required this.owner,
    required this.repository,
    HttpClient Function()? httpClientFactory,
    Uri? latestReleaseUri,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _latestReleaseUri =
           latestReleaseUri ??
           Uri.https(
             'api.github.com',
             '/repos/$owner/$repository/releases/latest',
           );

  final String owner;
  final String repository;
  final HttpClient Function() _httpClientFactory;
  final Uri _latestReleaseUri;

  Future<AppUpdateRelease> fetchLatestStableRelease() async {
    final releaseJson = await _readJson(_latestReleaseUri);
    final releaseMap = _requireMap(releaseJson, 'release response');
    final tag = _requireString(releaseMap, 'tag_name');
    final version = tag.replaceFirst(RegExp(r'^v'), '');
    final htmlUrl = _requireString(releaseMap, 'html_url');
    final isDraft = releaseMap['draft'] == true;
    final isPrerelease = releaseMap['prerelease'] == true;
    if (isDraft || isPrerelease) {
      throw const FormatException(
        'Latest GitHub release is not a stable published release.',
      );
    }

    final assets = releaseMap['assets'];
    if (assets is! List) {
      throw const FormatException('Release assets payload is missing.');
    }
    final manifestName = 'landa-v$version-release-manifest.json';
    final manifestAsset = assets
        .cast<Object?>()
        .map((asset) {
          return _requireMap(asset, 'release asset');
        })
        .firstWhere(
          (asset) => asset['name'] == manifestName,
          orElse: () => throw FormatException(
            'Stable release manifest asset is missing: $manifestName',
          ),
        );
    final manifestUrl = _requireString(manifestAsset, 'browser_download_url');
    final manifestJson = await _readJson(Uri.parse(manifestUrl));
    _validateStableManifest(
      manifestJson: manifestJson,
      expectedTag: tag,
      expectedVersion: version,
    );

    return AppUpdateRelease(
      version: version,
      tag: tag,
      releasePageUrl: htmlUrl,
    );
  }

  Future<Object?> _readJson(Uri uri) async {
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'LandaUpdateCheck/1.0');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub request failed with status ${response.statusCode}',
          uri: uri,
        );
      }
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  void _validateStableManifest({
    required Object? manifestJson,
    required String expectedTag,
    required String expectedVersion,
  }) {
    final manifest = _requireMap(manifestJson, 'release manifest');
    final schemaVersion = manifest['schemaVersion'];
    if (schemaVersion != AppUpdateConfig.manifestSchemaVersion) {
      throw FormatException(
        'Unsupported release manifest schema: $schemaVersion',
      );
    }
    final release = _requireMap(
      manifest['release'],
      'release manifest.release',
    );
    final channel = _requireString(release, 'channel');
    final tag = _requireString(release, 'tag');
    final version = _requireString(release, 'version');
    final draft = release['draft'] == true;
    final prerelease = release['prerelease'] == true;
    if (channel != AppUpdateConfig.stableChannel ||
        tag != expectedTag ||
        version != expectedVersion ||
        draft ||
        prerelease) {
      throw const FormatException(
        'Release manifest does not match stable release contract.',
      );
    }
  }

  Map<String, dynamic> _requireMap(Object? value, String fieldName) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('Expected object for $fieldName.');
  }

  String _requireString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw FormatException('Expected string for $key.');
  }
}
