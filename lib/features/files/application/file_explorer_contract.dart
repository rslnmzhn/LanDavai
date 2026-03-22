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
