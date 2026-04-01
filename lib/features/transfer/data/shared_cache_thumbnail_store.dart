import 'dart:typed_data';

/// Narrow artifact port for shared-cache thumbnail bytes and cached thumbnail
/// path reuse.
abstract class SharedCacheThumbnailStore {
  Future<Uint8List?> readOwnerThumbnailBytes({
    required String cacheId,
    required String thumbnailId,
  });

  Future<String?> resolveReceiverThumbnailPath({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
  });

  Future<String> saveReceiverThumbnailBytes({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
    required Uint8List bytes,
  });
}
