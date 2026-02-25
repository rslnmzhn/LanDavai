enum SharedFolderCacheRole { owner, receiver }

class SharedFolderIndexEntry {
  SharedFolderIndexEntry({
    required this.relativePath,
    required this.sizeBytes,
    required this.modifiedAtMs,
  });

  final String relativePath;
  final int sizeBytes;
  final int modifiedAtMs;

  Map<String, Object> toCompactJson() {
    return <String, Object>{
      'p': relativePath,
      's': sizeBytes,
      'm': modifiedAtMs,
    };
  }

  static SharedFolderIndexEntry fromCompactJson(Map<String, dynamic> json) {
    return SharedFolderIndexEntry(
      relativePath: json['p'] as String,
      sizeBytes: (json['s'] as num).toInt(),
      modifiedAtMs: (json['m'] as num).toInt(),
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
