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
        if (_matchesArch(asset: asset, preferredArch: preferredArch) &&
            asset.primary) {
          return asset;
        }
      }
      for (final asset in platformAssets) {
        if (_matchesArch(asset: asset, preferredArch: preferredArch)) {
          return asset;
        }
      }
    }

    if (target.platform == AppUpdateRuntimePlatform.android) {
      throw StateError(
        'No Android APK matches this device ABI: '
        '${target.archPreferences.join(', ')}.',
      );
    }

    final primaryAsset = platformAssets.where((asset) => asset.primary);
    if (primaryAsset.isNotEmpty) {
      return primaryAsset.first;
    }
    return platformAssets.first;
  }

  bool _matchesArch({
    required AppUpdateAsset asset,
    required String preferredArch,
  }) {
    final normalizedArch = _normalizeArch(asset.arch);
    final normalizedPreferred = _normalizeArch(preferredArch);
    if (normalizedArch == null || normalizedPreferred == null) {
      return false;
    }
    if (normalizedArch != normalizedPreferred) {
      return false;
    }
    if (asset.platform != 'android') {
      return true;
    }
    final fileName = asset.fileName.toLowerCase();
    return fileName.contains(normalizedArch.toLowerCase()) ||
        fileName.contains(normalizedArch.toLowerCase().replaceAll('-', '_'));
  }

  String? _normalizeArch(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('-', '_');
    if (value.isEmpty) {
      return null;
    }
    if (value == 'armeabi_v7a' || value == 'armv7l' || value == 'arm') {
      return 'armeabi-v7a';
    }
    if (value == 'arm64_v8a' || value == 'aarch64' || value == 'arm64') {
      return 'arm64-v8a';
    }
    if (value == 'x86_64' || value == 'amd64') {
      return 'x86_64';
    }
    return value;
  }
}
