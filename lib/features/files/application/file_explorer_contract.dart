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
    this.sourceToken,
    this.subtitle,
    this.sizeBytes,
    this.modifiedAt,
    this.changedAt,
    this.removableSharedCacheId,
  });

  final String path;
  final String virtualPath;
  final String? sourceToken;
  final String? subtitle;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final DateTime? changedAt;
  final String? removableSharedCacheId;
}

class FileExplorerVirtualFolder {
  const FileExplorerVirtualFolder({
    required this.name,
    required this.folderPath,
    this.sourceToken,
    this.removableSharedCacheId,
  });

  final String name;
  final String folderPath;
  final String? sourceToken;
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
