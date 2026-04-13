import 'dart:io';

import 'package:open_filex/open_filex.dart';

class PathOpener {
  Future<void> openPath(String path) async {
    final entityType = FileSystemEntity.typeSync(path, followLinks: false);
    if (entityType == FileSystemEntityType.notFound) {
      throw StateError('Path does not exist: $path');
    }
    if (entityType == FileSystemEntityType.directory) {
      await _openDirectory(path);
      return;
    }
    await _openFile(path);
  }

  Future<void> openContainingFolder(String path) async {
    final target = _resolveFolderTarget(path);
    await _openDirectory(target);
  }

  Future<void> _openDirectory(String path) async {
    if (Platform.isWindows) {
      final result = await Process.run('explorer.exe', <String>[path]);
      if (result.exitCode != 0) {
        throw StateError(
          result.stderr.toString().trim().isEmpty
              ? 'explorer.exe failed with exit code ${result.exitCode}.'
              : result.stderr.toString().trim(),
        );
      }
      return;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', <String>[path]);
      if (result.exitCode != 0) {
        throw StateError(
          result.stderr.toString().trim().isEmpty
              ? 'xdg-open failed with exit code ${result.exitCode}.'
              : result.stderr.toString().trim(),
        );
      }
      return;
    }

    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<void> _openFile(String path) async {
    if (Platform.isWindows) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        throw StateError(result.message);
      }
      return;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', <String>[path]);
      if (result.exitCode != 0) {
        throw StateError(
          result.stderr.toString().trim().isEmpty
              ? 'xdg-open failed with exit code ${result.exitCode}.'
              : result.stderr.toString().trim(),
        );
      }
      return;
    }

    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  String _resolveFolderTarget(String path) {
    final entity = FileSystemEntity.typeSync(path, followLinks: false);
    if (entity == FileSystemEntityType.directory) {
      return path;
    }
    return File(path).parent.path;
  }
}
