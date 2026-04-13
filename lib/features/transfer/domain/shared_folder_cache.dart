enum SharedFolderCacheRole { owner, receiver }

class SharedFolderTreeFingerprint {
  const SharedFolderTreeFingerprint({
    required this.relativeFolderPath,
    required this.fingerprint,
    required this.itemCount,
    required this.totalBytes,
  });

  final String relativeFolderPath;
  final String fingerprint;
  final int itemCount;
  final int totalBytes;
}

class SharedCacheScopedSelection {
  const SharedCacheScopedSelection({
    required this.entries,
    required this.fingerprint,
    required this.itemCount,
    required this.totalBytes,
  });

  final List<SharedFolderIndexEntry> entries;
  final String fingerprint;
  final int itemCount;
  final int totalBytes;
}

class SharedFolderIndexEntry {
  SharedFolderIndexEntry({
    required this.relativePath,
    required this.sizeBytes,
    required this.modifiedAtMs,
    this.absolutePath,
    this.thumbnailId,
    this.sha256,
  });

  final String relativePath;
  final int sizeBytes;
  final int modifiedAtMs;
  final String? absolutePath;
  final String? thumbnailId;
  final String? sha256;

  SharedFolderIndexEntry copyWith({
    String? relativePath,
    int? sizeBytes,
    int? modifiedAtMs,
    String? absolutePath,
    bool clearAbsolutePath = false,
    String? thumbnailId,
    bool clearThumbnailId = false,
    String? sha256,
    bool clearSha256 = false,
  }) {
    return SharedFolderIndexEntry(
      relativePath: relativePath ?? this.relativePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedAtMs: modifiedAtMs ?? this.modifiedAtMs,
      absolutePath: clearAbsolutePath
          ? null
          : (absolutePath ?? this.absolutePath),
      thumbnailId: clearThumbnailId ? null : (thumbnailId ?? this.thumbnailId),
      sha256: clearSha256 ? null : (sha256 ?? this.sha256),
    );
  }

  Map<String, Object?> toCompactJson() {
    final json = <String, Object?>{
      'p': relativePath,
      's': sizeBytes,
      'm': modifiedAtMs,
    };
    if (absolutePath != null) {
      json['a'] = absolutePath;
    }
    if (thumbnailId != null && thumbnailId!.isNotEmpty) {
      json['t'] = thumbnailId;
    }
    if (sha256 != null && sha256!.isNotEmpty) {
      json['h'] = sha256;
    }
    return json;
  }

  static SharedFolderIndexEntry fromCompactJson(Map<String, dynamic> json) {
    return SharedFolderIndexEntry(
      relativePath: json['p'] as String,
      sizeBytes: (json['s'] as num).toInt(),
      modifiedAtMs: (json['m'] as num).toInt(),
      absolutePath: json['a'] as String?,
      thumbnailId: json['t'] as String?,
      sha256: json['h'] as String?,
    );
  }
}

class SharedFolderCacheRecord {
  SharedFolderCacheRecord({
    required this.cacheId,
    required this.role,
    required this.ownerMacAddress,
    required this.rootPath,
    required this.displayName,
    required this.indexFilePath,
    required this.itemCount,
    required this.totalBytes,
    required this.updatedAtMs,
    this.peerMacAddress,
  });

  final String cacheId;
  final SharedFolderCacheRole role;
  final String ownerMacAddress;
  final String? peerMacAddress;
  final String rootPath;
  final String displayName;
  final String indexFilePath;
  final int itemCount;
  final int totalBytes;
  final int updatedAtMs;

  Map<String, Object?> toDbMap() {
    return <String, Object?>{
      'cache_id': cacheId,
      'role': role.name,
      'owner_mac_address': ownerMacAddress,
      'peer_mac_address': peerMacAddress,
      'root_path': rootPath,
      'display_name': displayName,
      'index_file_path': indexFilePath,
      'item_count': itemCount,
      'total_bytes': totalBytes,
      'updated_at': updatedAtMs,
    };
  }

  static SharedFolderCacheRecord fromDbMap(Map<String, Object?> map) {
    return SharedFolderCacheRecord(
      cacheId: map['cache_id'] as String,
      role: SharedFolderCacheRole.values.byName(map['role'] as String),
      ownerMacAddress: map['owner_mac_address'] as String,
      peerMacAddress: map['peer_mac_address'] as String?,
      rootPath: map['root_path'] as String,
      displayName: map['display_name'] as String,
      indexFilePath: map['index_file_path'] as String,
      itemCount: (map['item_count'] as num).toInt(),
      totalBytes: (map['total_bytes'] as num).toInt(),
      updatedAtMs: (map['updated_at'] as num).toInt(),
    );
  }
}
