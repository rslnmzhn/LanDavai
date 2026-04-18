import '../domain/app_update_models.dart';

class AppUpdateAssetSelector {
  const AppUpdateAssetSelector();

  AppUpdateAsset selectAsset({
    required AppUpdateRelease release,
    required AppUpdateTarget target,
  }) {
    final platformName = switch (target.platform) {
      AppUpdateRuntimePlatform.android => 'android',
      AppUpdateRuntimePlatform.windows => 'windows',
      AppUpdateRuntimePlatform.linux => 'linux',
      AppUpdateRuntimePlatform.macos => 'macos',
      AppUpdateRuntimePlatform.unsupported => throw StateError(
        'Updates are not supported on this platform yet.',
      ),
    };

    final platformAssets = release.assets
        .where((asset) => asset.platform == platformName)
        .toList(growable: false);
    if (platformAssets.isEmpty) {
      throw StateError(
        'No release asset is available for platform "$platformName".',
      );
    }

    for (final preferredArch in target.archPreferences) {
      for (final asset in platformAssets) {
        if (asset.arch == preferredArch && asset.primary) {
          return asset;
        }
      }
      for (final asset in platformAssets) {
        if (asset.arch == preferredArch) {
          return asset;
        }
      }
    }

    final primaryAsset = platformAssets.where((asset) => asset.primary);
    if (primaryAsset.isNotEmpty) {
      return primaryAsset.first;
    }
    return platformAssets.first;
  }
}
