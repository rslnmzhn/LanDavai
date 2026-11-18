import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'nearby_transfer_transport_adapter.dart';

class NearbyTransferFilePicker {
  NearbyTransferFilePicker({
    bool? supportsDirectoryPickingOverride,
    Future<FilePickerResult?> Function()? pickFilesInvoker,
    Future<String?> Function()? pickDirectoryPathInvoker,
  }) : _supportsDirectoryPickingOverride = supportsDirectoryPickingOverride,
       _pickFilesInvoker = pickFilesInvoker,
       _pickDirectoryPathInvoker = pickDirectoryPathInvoker;

  final bool? _supportsDirectoryPickingOverride;
  final Future<FilePickerResult?> Function()? _pickFilesInvoker;
  final Future<String?> Function()? _pickDirectoryPathInvoker;

  bool get supportsDirectoryPicking =>
      _supportsDirectoryPickingOverride ??
      Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS;

  Future<NearbyTransferSelection?> pickFiles() async {
    final result =
        await (_pickFilesInvoker?.call() ??
            FilePicker.platform.pickFiles(
              allowMultiple: true,
              withData: false,
            ));
    final paths =
        result?.paths
            .whereType<String>()
            .where((path) => path.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    if (paths.isEmpty) {
      return null;
    }

    final entries = <NearbyTransferPickedEntry>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }
      entries.add(
        NearbyTransferPickedEntry(
          sourcePath: path,
          relativePath: p.basename(path),
          sizeBytes: stat.size,
        ),
      );
    }
    if (entries.isEmpty) {
      return null;
    }

    return NearbyTransferSelection(
      label: entries.length == 1 ? entries.first.relativePath : 'Файлы',
      entries: List<NearbyTransferPickedEntry>.unmodifiable(entries),
    );
  }

  Future<NearbyTransferSelection?> pickDirectory() async {
    if (!supportsDirectoryPicking) {
      return null;
    }

    final path =
        await (_pickDirectoryPathInvoker?.call() ??
            FilePicker.platform.getDirectoryPath());
    if (path == null || path.trim().isEmpty) {
      return null;
    }

    final directory = Directory(path.trim());
    if (!await directory.exists()) {
      return null;
    }

    final rootName = p.basename(directory.path);
    final entries = <NearbyTransferPickedEntry>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }
      final relativeWithinRoot = p.relative(entity.path, from: directory.path);
      entries.add(
        NearbyTransferPickedEntry(
          sourcePath: entity.path,
          relativePath: p.join(rootName, relativeWithinRoot),
          sizeBytes: stat.size,
        ),
      );
    }
    if (entries.isEmpty) {
      return null;
    }

    return NearbyTransferSelection(
      label: rootName,
      entries: List<NearbyTransferPickedEntry>.unmodifiable(entries),
    );
  }
}
