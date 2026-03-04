part of '../file_explorer_page.dart';

class FileExplorerRoot {
  const FileExplorerRoot({
    required this.label,
    required this.path,
    this.isSharedFolder = false,
    this.virtualFiles = const <FileExplorerVirtualFile>[],
    this.virtualFilesLoader,
    this.virtualDirectoryLoader,
  });

  final String label;
  final String path;
  final bool isSharedFolder;
  final List<FileExplorerVirtualFile> virtualFiles;
  final Future<List<FileExplorerVirtualFile>> Function()? virtualFilesLoader;
  final Future<FileExplorerVirtualDirectory> Function(String folderPath)?
  virtualDirectoryLoader;

  bool get isVirtual =>
      virtualFiles.isNotEmpty ||
      virtualFilesLoader != null ||
      virtualDirectoryLoader != null;
}

class FileExplorerVirtualFile {
  const FileExplorerVirtualFile({
    required this.path,
    required this.virtualPath,
    this.subtitle,
    this.sizeBytes,
    this.modifiedAt,
    this.changedAt,
  });

  final String path;
  final String virtualPath;
  final String? subtitle;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final DateTime? changedAt;
}

class FileExplorerVirtualFolder {
  const FileExplorerVirtualFolder({
    required this.name,
    required this.folderPath,
    this.removableSharedCacheId,
  });

  final String name;
  final String folderPath;
  final String? removableSharedCacheId;
}

class FileExplorerVirtualDirectory {
  const FileExplorerVirtualDirectory({
    this.folders = const <FileExplorerVirtualFolder>[],
    this.files = const <FileExplorerVirtualFile>[],
  });

  final List<FileExplorerVirtualFolder> folders;
  final List<FileExplorerVirtualFile> files;
}

const Set<String> _supportedImageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.heic',
  '.heif',
  '.tif',
  '.tiff',
};

const Set<String> _supportedVideoExtensions = <String>{
  '.mp4',
  '.mov',
  '.mkv',
  '.avi',
  '.webm',
  '.m4v',
  '.3gp',
  '.mpeg',
  '.mpg',
};

const Set<String> _supportedAudioExtensions = <String>{
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.wav',
  '.ogg',
  '.opus',
  '.wma',
};

const Set<String> _supportedTextExtensions = <String>{
  '.txt',
  '.md',
  '.log',
  '.json',
  '.yaml',
  '.yml',
  '.csv',
  '.xml',
};

bool get _useMediaKitForPlayback =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

enum SharedRecacheActionResult { started, refreshedOnly, cancelled }

class SharedRecacheProgressDetails {
  const SharedRecacheProgressDetails({
    required this.processedFiles,
    required this.totalFiles,
    required this.currentCacheLabel,
    required this.currentRelativePath,
    required this.eta,
  });

  final int processedFiles;
  final int totalFiles;
  final String currentCacheLabel;
  final String currentRelativePath;
  final Duration? eta;
}

enum _ExplorerSortOption {
  nameAsc,
  nameDesc,
  modifiedNewest,
  modifiedOldest,
  changedNewest,
  changedOldest,
  sizeLargest,
  sizeSmallest,
}

enum _ExplorerViewMode { list, grid }

enum _ExplorerMenuAction {
  sortNameAsc,
  sortNameDesc,
  sortModifiedNewest,
  sortModifiedOldest,
  sortChangedNewest,
  sortChangedOldest,
  sortSizeLargest,
  sortSizeSmallest,
}

class _ExplorerEntityRecord {
  const _ExplorerEntityRecord({
    required this.isDirectory,
    required this.name,
    required this.subtitle,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.changedAt,
    this.filePath,
    this.virtualFolderPath,
    this.removableSharedCacheId,
  });

  final bool isDirectory;
  final String name;
  final String subtitle;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime changedAt;
  final String? filePath;
  final String? virtualFolderPath;
  final String? removableSharedCacheId;

  static _ExplorerEntityRecord fromReal({
    required FileSystemEntity entity,
    required FileStat stat,
  }) {
    return _ExplorerEntityRecord(
      isDirectory: entity is Directory,
      name: p.basename(entity.path),
      subtitle: entity.path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      changedAt: stat.changed,
      filePath: entity.path,
    );
  }

  static _ExplorerEntityRecord virtualFolder({
    required String name,
    required String folderPath,
    String? removableSharedCacheId,
  }) {
    return _ExplorerEntityRecord(
      isDirectory: true,
      name: name,
      subtitle: folderPath,
      sizeBytes: 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      changedAt: DateTime.fromMillisecondsSinceEpoch(0),
      virtualFolderPath: folderPath,
      removableSharedCacheId: removableSharedCacheId,
    );
  }

  static _ExplorerEntityRecord virtualFile({
    required File file,
    required FileStat stat,
    required String subtitle,
  }) {
    return _ExplorerEntityRecord(
      isDirectory: false,
      name: p.basename(file.path),
      subtitle: subtitle,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      changedAt: stat.changed,
      filePath: file.path,
    );
  }

  static _ExplorerEntityRecord virtualFileCached({
    required String filePath,
    required String name,
    required String subtitle,
    required int sizeBytes,
    required DateTime modifiedAt,
    required DateTime changedAt,
  }) {
    return _ExplorerEntityRecord(
      isDirectory: false,
      name: name,
      subtitle: subtitle,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      changedAt: changedAt,
      filePath: filePath,
    );
  }
}
